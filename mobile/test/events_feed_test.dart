import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:siaga_bencana/app.dart';
import 'package:siaga_bencana/features/notifications/local_notification_service.dart';
import 'package:siaga_bencana/core/network/api_client.dart';
import 'package:siaga_bencana/core/session/session_coordinator.dart';
import 'package:siaga_bencana/core/utils/time_format.dart';
import 'package:siaga_bencana/features/auth/auth_dto.dart';
import 'package:siaga_bencana/features/event_detail/event_detail_screen.dart';
import 'package:siaga_bencana/features/events/event_dto.dart';
import 'package:siaga_bencana/features/events/event_feed_view_model.dart';
import 'package:siaga_bencana/features/events/event_repository.dart';
import 'package:siaga_bencana/features/home/home_screen.dart';
import 'package:siaga_bencana/features/zone/zone_repository.dart';
import 'package:siaga_bencana/features/zone/zone_view_model.dart';

import 'widget_test.dart' show authJson, base, FakeLocationService, meta, ok, signedIn, zoneJson;

const quakeId = '30000000-0000-4000-8000-000000000001';
const weatherId = '30000000-0000-4000-8000-000000000002';
const at = '2026-11-20T01:00:00Z';
const reasonText = 'Jarak kejadian berada dalam radius pantau.';
typedef Json = Map<String, dynamic>;

Json event({bool weather = false, bool missing = false, String? lifecycle}) => {
  'id': weather ? weatherId : quakeId,
  'source': weather ? 'BMKG_NOWCAST' : 'BMKG_TEWS',
  'category': weather ? 'extreme_weather' : 'earthquake',
  'title': weather ? 'Peringatan cuaca' : 'Gempa sekitar Surabaya',
  'occurred_at': at, 'latitude': -7.25, 'longitude': 112.75,
  'is_simulated': true, 'content_version': 1,
  'lifecycle_status': lifecycle ?? (weather ? 'expired' : 'current'),
  'priority': {
    'priority_algo': weather ? 'cap-priority-v1' : 'eq-priority-v1',
    'priority_score': weather || missing ? null : 74.25,
    'priority_display': weather || missing ? null : '74.3',
    'priority_label': weather ? 'information' : missing ? 'unavailable' : 'high',
    'priority_reasons': [
      {'code': 'distance_radius', 'text': reasonText, 'values': {'radius_km': 50}},
      if (missing) {'code': 'magnitude', 'text': 'Magnitudo belum tersedia', 'values': {'magnitude': null}},
    ],
    'components': weather || missing ? null : {'P': 1.0},
    'match_method': weather ? 'near_polygon_sample' : 'point_distance',
    'match_distance_km': 1.2, 'within_radius': true, 'evaluated_at': at, 'zone_version': 1,
  },
  'cap': weather ? {
    'severity': 'Severe', 'urgency': 'Immediate', 'certainty': 'Likely',
    'effective': at, 'expires': '2026-11-20T02:00:00Z', 'area_descriptions': ['Surabaya'],
  } : null,
};

Json feed(List<Json> items, {int version = 1, int offset = 0, int? next, String state = 'stale'}) => {
  'items': items,
  'page': {'offset': offset, 'limit': 20, 'next_offset': next, 'has_more': next != null},
  'meta': {
    ...meta, 'mode': 'simulation', 'is_simulated': true, 'zone_version': version,
    'sources': [
      {'source': 'BMKG_TEWS', 'state': 'healthy', 'last_success_at': at, 'last_attempt_at': at},
      {'source': 'BMKG_NOWCAST', 'state': state, 'last_success_at': state == 'unavailable' ? null : at,
        'last_attempt_at': at},
    ],
  },
};

http.Response response(Json body, [int status = 200]) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), status);

http.Response failure(String code, int status) =>
    response({'code': code, 'message': 'Gagal memuat.', 'request_id': 'test', 'details': null}, status);

EventFeedViewModel model(Future<http.Response> Function(http.Request) handler) {
  final session = signedIn();
  final api = ApiClient(client: MockClient(handler), baseUrl: base, session: session);
  final zone = ZoneViewModel(ZoneRepository(api), session, FakeLocationService());
  final vm = EventFeedViewModel(EventRepository(api), session, zone);
  addTearDown(() {
    vm.dispose();
    zone.dispose();
    api.close();
    session.dispose();
  });
  return vm;
}

Future<void> openHome(WidgetTester tester, Future<http.Response> Function(http.Request) events) async {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final session = signedIn();
  addTearDown(session.dispose);
  await tester.pumpWidget(SiagaApp(
    autoStartNotifications: false,
    localNotificationService: const NoopLocalNotificationService(),
    baseUrl: base, session: session, initialLocation: '/home', textScaler: const TextScaler.linear(2),
    client: MockClient((request) async {
      if (request.url.path.endsWith('/events')) return events(request);
      if (request.url.path.endsWith('/me/zone')) return ok(zoneJson);
      return ok({'status': 'ok'});
    }),
  ));
  await tester.pumpAndSettle();
}

Future<void> reveal(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(finder, 220, scrollable: find.byType(Scrollable).first);
  await tester.pumpAndSettle();
}

Future<void> closeHome(WidgetTester tester) async {
  final session = tester.element(find.byType(Scaffold).first).read<SessionCoordinator>();
  await tester.pumpWidget(const SizedBox.shrink());
  session.clear();
}

void main() {
  test('local dates include local time and explicit offset, distance preserves zero', () {
    final local = DateTime(2026, 11, 20, 8, 5);
    final short = formatLocalDateTime(local.toUtc());
    expect(short, startsWith('20 Nov 2026, 08:05 '));
    expect(short, matches(RegExp(r'(WIB|WITA|WIT|UTC[+-]\d\d:\d\d)$')));
    expect(formatFullTooltipDateTime(local.toUtc()), startsWith('Jumat, 20 November 2026'));
    expect(formatDistanceKm(0), 'Di titik pantau');
    expect(formatDistanceKm(0.01), '0 km');
    expect(formatDistanceKm(1.24), '1.2 km');
  });

  test('feed preserves server display, null score and CAP lifecycle', () {
    final items = EventFeedDto.fromJson(feed([event(), event(missing: true)])).items;
    expect(items.first.priority.priorityScore, 74.25);
    expect(items.first.priority.priorityDisplay, '74.3');
    expect(items.last.priority.priorityScore, isNull);
    expect(items.last.priority.priorityDisplay, isNull);
    expect(items.last.priority.priorityReasons.last.values, {'magnitude': null});
    for (final status in ['active', 'scheduled', 'expired', 'cancelled', 'superseded', 'incomplete']) {
      final row = EventSummaryDto.fromJson(event(weather: true, lifecycle: status));
      expect(row.lifecycleStatus, status);
      expect(row.cap!.areaDescriptions, ['Surabaya']);
    }
  });

  test('invalid enums and nonpositive versions throw FormatException', () {
    final row = event();
    for (final key in ['source', 'category', 'lifecycle_status', 'content_version']) {
      expect(() => EventSummaryDto.fromJson({...row, key: key == 'content_version' ? 0 : 'unknown'}),
          throwsFormatException);
    }
    for (final key in ['priority_algo', 'priority_label', 'match_method', 'zone_version']) {
      expect(() => PriorityDto.fromJson({...row['priority'] as Json, key: key == 'zone_version' ? 0 : 'unknown'}),
          throwsFormatException);
    }
    expect(() => EventFeedDto.fromJson(feed([], version: 0)), throwsFormatException);
    expect(() => SourceFreshnessDto.fromJson({'source': 'BMKG_TEWS', 'state': 'unknown'}), throwsFormatException);
  });

  test('authenticated GET encodes defaults and resets incompatible filters', () async {
    late http.Request last;
    final vm = model((request) async {
      last = request;
      return response(feed([]));
    });
    await vm.refresh();
    expect(last.method, 'GET');
    expect(last.url.path, '/api/v1/events');
    expect(last.headers['Authorization'], 'Bearer memory-token');
    expect(last.url.queryParameters, {'radius_only': 'true', 'weather_status': 'active',
      'sort': 'recent', 'limit': '20', 'offset': '0'});
    await vm.setFilters(category: 'earthquake', radiusOnly: false, sort: 'priority');
    expect(last.url.queryParameters['sort'], 'priority');
    await vm.setFilters(category: 'extreme_weather', radiusOnly: false, weatherStatus: 'all');
    expect(last.url.queryParameters['sort'], 'recent');
    expect(last.url.queryParameters['weather_status'], 'all');
    await vm.setFilters(category: null, radiusOnly: true);
    expect(last.url.queryParameters['weather_status'], 'active');
    expect(last.url.queryParameters.containsKey('category'), false);
  });

  test('refresh and pagination failures retain cache, retry uses next_offset and deduplicates', () async {
    var offline = false;
    final offsets = <String>[];
    final vm = model((request) async {
      final offset = request.url.queryParameters['offset']!;
      offsets.add(offset);
      if (offline) return failure('SERVICE_UNAVAILABLE', 503);
      if (offset == '0') return response(feed([event()], next: 20));
      return response(feed([event(), event(weather: true)], offset: 20));
    });
    final first = vm.refresh();
    expect(vm.initialLoading, true);
    await first;
    final stamp = vm.lastLoadedAt;
    final cached = vm.meta;
    offline = true;
    final refresh = vm.refresh();
    expect(vm.refreshing, true);
    await refresh;
    expect(vm.error, isNotNull);
    expect(vm.meta, same(cached));
    final more = vm.loadMore();
    expect(vm.loadingMore, true);
    await more;
    expect(vm.loadMoreError, isNotNull);
    expect(vm.lastLoadedAt, stamp);
    expect(vm.items.single.id, quakeId);
    offline = false;
    await vm.loadMore();
    expect(vm.loadMoreError, isNull);
    expect(vm.items.map((item) => item.id), [quakeId, weatherId]);
    expect(offsets, ['0', '0', '20', '20']);
  });

  test('late response cannot restore previous session', () async {
    final pending = Completer<http.Response>();
    final vm = model((_) => pending.future);
    final load = vm.setFilters(category: 'earthquake', radiusOnly: false, sort: 'priority');
    vm.session.clear();
    vm.session.establish(AuthData.fromJson(authJson()));
    pending.complete(response(feed([event()])));
    await load;
    expect(vm.items, isEmpty);
    expect(vm.lastLoadedAt, isNull);
    expect(vm.meta, isNull);
    expect(vm.error, isNull);
    expect(vm.radiusOnly, true);
    expect(vm.category, isNull);
    expect(vm.initialLoading, false);
  });

  test('zone update reloads and rejects older request and older server metadata', () async {
    final pending = Completer<http.Response>();
    var calls = 0;
    var version = 2;
    final vm = model((request) async {
      if (request.url.path.endsWith('/me/zone')) return ok({...zoneJson, 'zone_version': 2});
      calls++;
      if (calls == 1) return pending.future;
      return response(feed([event(weather: true)], version: version));
    });
    final first = vm.refresh();
    await Future<void>.delayed(Duration.zero);
    await vm.zone.load();
    await Future<void>.delayed(Duration.zero);
    expect(vm.meta?.zoneVersion, 2);
    pending.complete(response(feed([event()])));
    await first;
    expect(vm.items.single.id, weatherId);
    version = 1;
    await vm.refresh();
    expect(vm.error, isNotNull);
    expect(vm.meta?.zoneVersion, 2);
    expect(calls, 3);
  });

  test('409 ZONE_REQUIRED clears obsolete zone data', () async {
    var needsZone = false;
    final vm = model((_) async => needsZone ? failure('ZONE_REQUIRED', 409) : response(feed([event()])));
    await vm.refresh();
    needsZone = true;
    await vm.refresh();
    expect(vm.zoneRequired, true);
    expect(vm.items, isEmpty);
    expect(vm.initialLoading || vm.refreshing, false);
  });

  testWidgets('quake reasons, simulation, cached freshness and detail at 360px / 200%', (tester) async {
    var offline = false;
    await openHome(tester, (_) async =>
        offline ? failure('SERVICE_UNAVAILABLE', 503) : response(feed([event()])));
    final vm = tester.element(find.byType(HomeScreen)).read<EventFeedViewModel>();
    offline = true;
    await vm.refresh();
    await tester.pumpAndSettle();
    expect(find.text('SIMULASI — data demo'), findsOneWidget);
    expect(find.text('BMKG Gempa — Aktif'), findsOneWidget);
    expect(find.text('BMKG Cuaca — Belum diperbarui'), findsOneWidget);
    await reveal(tester, find.textContaining('Data terakhir dimuat'));
    await reveal(tester, find.text('Prioritas 74.3 — Tinggi'));
    expect(find.text('SIMULASI'), findsOneWidget);
    final why = find.text('Mengapa?');
    await reveal(tester, why);
    await tester.tap(why);
    await tester.pumpAndSettle();
    await reveal(tester, find.text(reasonText));
    final detail = find.text('Lihat Detail');
    await reveal(tester, detail);
    await tester.tap(detail);
    await tester.pumpAndSettle();
    final screen = tester.element(find.byType(EventDetailScreen));
    expect(tester.widget<EventDetailScreen>(find.byType(EventDetailScreen)).eventId, quakeId);
    expect(GoRouter.of(screen).state.uri.path, '/events/$quakeId');
    expect(tester.takeException(), isNull);
    await closeHome(tester);
  });

  testWidgets('inactive CAP shows lifecycle and location method at 360px / 200%', (tester) async {
    await openHome(tester, (request) async => response(feed(
      request.url.queryParameters['weather_status'] == 'all' ? [event(weather: true)] : [],
    )));
    final vm = tester.element(find.byType(HomeScreen)).read<EventFeedViewModel>();
    await vm.setFilters(category: 'extreme_weather', radiusOnly: false, weatherStatus: 'all');
    await tester.pumpAndSettle();
    await reveal(tester, find.text('Kedaluwarsa'));
    await reveal(tester, find.text('Perkiraan jarak centroid/vertex (bukan irisan eksak)'));
    expect(find.text('Keparahan: Parah'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await closeHome(tester);
  });

  testWidgets('empty nearby results offer all and zone edit with unavailable source', (tester) async {
    await openHome(tester, (_) async => response(feed([], state: 'unavailable')));
    expect(find.text('BMKG Cuaca — Tidak tersedia'), findsOneWidget);
    expect(find.textContaining('Belum pernah berhasil diperbarui.'), findsOneWidget);
    await reveal(tester, find.text('Belum ada informasi yang cocok dengan radius ini.'));
    expect(find.text('Sebagian data sumber belum tersedia.'), findsOneWidget);
    expect(find.textContaining(RegExp('Belum ada.*aman')), findsNothing);
    final all = find.widgetWithText(OutlinedButton, 'Semua');
    await reveal(tester, all);
    await tester.tap(all);
    await tester.pumpAndSettle();
    expect(find.text('Belum ada informasi yang cocok dengan filter ini.'), findsOneWidget);
    final edit = find.widgetWithText(OutlinedButton, 'Ubah Zona');
    await reveal(tester, edit);
    await tester.tap(edit);
    await tester.pumpAndSettle();
    expect(GoRouter.of(tester.element(find.byType(Scaffold).first)).routeInformationProvider.value.uri.toString(),
        '/account?edit=zone');
    expect(tester.takeException(), isNull);
    await closeHome(tester);
  });
}
