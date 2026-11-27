import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:siaga_bencana/app.dart';
import 'package:siaga_bencana/features/notifications/local_notification_service.dart';
import 'package:siaga_bencana/core/network/api_client.dart';
import 'package:siaga_bencana/core/session/session_coordinator.dart';
import 'package:siaga_bencana/features/event_detail/event_detail_screen.dart';
import 'package:siaga_bencana/features/map/map_dto.dart';
import 'package:siaga_bencana/features/map/map_repository.dart';
import 'package:siaga_bencana/features/map/map_screen.dart';
import 'package:siaga_bencana/features/map/map_view_model.dart';
import 'package:siaga_bencana/features/zone/zone_repository.dart';
import 'package:siaga_bencana/features/zone/zone_view_model.dart';

import 'events_feed_test.dart' show Json, failure, feed, quakeId, response, weatherId;
import 'widget_test.dart' show FakeLocationService, TestTileProvider, base, emptyFeed, ok,
    signedIn, tapVisible, zoneJson;

const reportId = '40000000-0000-4000-8000-000000000001';
Json marker(String id) => {
  'id': id, 'kind': id == reportId ? 'report' : 'event',
  'source': id == reportId ? 'CITIZEN' : id == weatherId ? 'BMKG_NOWCAST' : 'BMKG_TEWS',
  'category': id == reportId ? 'flood' : id == weatherId ? 'extreme_weather' : 'earthquake',
  'title': id == reportId ? 'Genangan warga' : id == quakeId ? 'Gempa lokal' : 'Cuaca lokal',
  'latitude': -7.25, 'longitude': id == reportId ? 112.95 : id == quakeId ? 112.55 : 112.75,
  'match_method': id == weatherId ? 'inside_polygon' : 'point_distance',
  'match_distance_km': 1.5, 'priority_label': id == reportId ? null : 'attention',
  'is_simulated': true,
};

Json markers(List<String> ids, {bool truncated = false, int version = 1}) => {
  'cap': 100, 'truncated': truncated, 'items': ids.map(marker).toList(),
  'meta': feed([], state: 'healthy', version: version)['meta'],
};

MapViewModel model(Future<http.Response> Function(http.Request) handler) {
  final session = signedIn();
  final api = ApiClient(client: MockClient(handler), baseUrl: base, session: session);
  final zone = ZoneViewModel(ZoneRepository(api), session, FakeLocationService());
  final vm = MapViewModel(MapRepository(api), session, zone);
  addTearDown(() {
    vm.dispose();
    zone.dispose();
    api.close();
    session.dispose();
  });
  return vm;
}

Future<List<Uri>> openBrowse(WidgetTester tester, Json data, {bool broken = false}) async {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final requests = <Uri>[];
  final session = signedIn();
  addTearDown(session.dispose);
  await tester.pumpWidget(SiagaApp(
    autoStartNotifications: false,
    localNotificationService: const NoopLocalNotificationService(),
    session: session, baseUrl: base, initialLocation: '/map',
    tileProvider: TestTileProvider(broken: broken), textScaler: const TextScaler.linear(2),
    client: MockClient((request) async {
      requests.add(request.url);
      if (request.url.path.endsWith('/map/markers')) return response(data);
      if (request.url.path.endsWith('/me/zone')) return ok(zoneJson);
      if (request.url.path.endsWith('/events')) return emptyFeed();
      return ok({'status': 'ok'});
    }),
  ));
  await tester.pumpAndSettle();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpAndSettle();
  return requests;
}

Future<void> closeApp(WidgetTester tester) async {
  final session = tester.element(find.byType(Scaffold).first).read<SessionCoordinator>();
  await tester.pumpWidget(const SizedBox.shrink());
  session.clear();
  expect(tester.takeException(), isNull);
}

void main() {
  test('marker feed validates enums, bounded coordinates, distance and cap', () {
    final json = markers([quakeId, reportId]);
    final parsed = MarkerFeedDto.fromJson(json);
    expect(parsed.items.first.source, 'BMKG_TEWS');
    expect(parsed.items.last.kind, 'report');
    expect(parsed.items.last.priorityLabel, isNull);
    expect(() => MarkerFeedDto.fromJson({...json, 'cap': 99}), throwsFormatException);
    for (final key in ['source', 'kind', 'category', 'match_method', 'priority_label']) {
      expect(() => MapMarkerDto.fromJson({...marker(quakeId), key: 'invalid'}), throwsFormatException);
    }
    for (final (key, value) in [
      ('latitude', -91.0), ('latitude', double.nan), ('longitude', 181.0),
      ('longitude', double.infinity), ('match_distance_km', -1.0),
    ]) {
      expect(() => MapMarkerDto.fromJson({...marker(quakeId), key: value}), throwsFormatException);
    }
  });

  test('bbox retains crossing direction on either side and clamps full worlds', () {
    List<double> bbox(double center, double width) {
      final bounds = LatLngBounds.worldSafe(north: 1, south: -0.0,
          longitudeCenter: center, longitudeWidth: width);
      final value = formatViewportBbox(bounds);
      expect(value, isNot(contains('-0.0')));
      return value.split(',').map(double.parse).toList();
    }
    expect(bbox(112, 2), [111, 0, 113, 1]);
    expect(bbox(-179, 4), [179, 0, -177, 1]);
    expect(bbox(179, 4), [177, 0, -179, 1]);
    for (final width in [360.0, 720.0]) {
      expect(bbox(179, width), [-180, 0, 180, 1]);
    }
  });

  testWidgets('viewport debounce coalesces changes and rejects responses during the wait', (tester) async {
    final requests = <http.Request>[];
    final first = Completer<http.Response>();
    final vm = model((request) async {
      requests.add(request);
      if (requests.length == 1) return first.future;
      return response(markers([weatherId]));
    });
    vm.onViewportChanged('1,0,2,1');
    await tester.pump(const Duration(milliseconds: 200));
    vm.onViewportChanged('2,0,3,1');
    await tester.pump(const Duration(milliseconds: 299));
    expect(requests, isEmpty);
    await tester.pump(const Duration(milliseconds: 1));
    expect(requests.single.url.queryParameters, {
      'bbox': '2,0,3,1', 'include_reports': 'true', 'radius_only': 'true',
    });
    expect(requests.single.headers['Authorization'], 'Bearer memory-token');
    vm.onViewportChanged('3,0,4,1');
    first.complete(response(markers([quakeId])));
    await tester.pump();
    expect(vm.items, isEmpty);
    await tester.pump(const Duration(milliseconds: 300));
    expect(vm.items.single.id, weatherId);
    expect(requests, hasLength(2));
    vm.session.clear();
  });

  test('filter changes supersede requests, errors retain cache, logout clears it', () async {
    final requests = <Uri>[];
    final first = Completer<http.Response>();
    final last = Completer<http.Response>();
    var state = 'ok';
    final vm = model((request) async {
      requests.add(request.url);
      if (requests.length == 1) return first.future;
      if (state == 'pending') return last.future;
      if (state == 'offline') throw http.ClientException('offline');
      if (state == 'zone') return failure('ZONE_REQUIRED', 409);
      return response(markers([reportId, reportId], truncated: true));
    });
    final old = vm.ensureInitialLoad(fallbackBbox: '179,-1,-179,1');
    await Future<void>.delayed(Duration.zero);
    await vm.setCategory('flood');
    first.complete(response(markers([quakeId])));
    await old;
    expect(vm.items.single.id, reportId);
    expect(vm.truncated, isTrue);
    await vm.setRadiusOnly(false);
    await vm.setIncludeReports(false);
    await vm.toggleListMode();
    expect(vm.listMode, isTrue);
    expect(requests.last.path, '/api/v1/map/markers');
    expect(requests.last.queryParameters, {
      'bbox': '179,-1,-179,1', 'radius_only': 'false', 'category': 'flood', 'include_reports': 'false',
    });
    final stamp = vm.lastLoadedAt;
    state = 'offline';
    await vm.retry();
    expect(vm.error, isNotNull);
    expect(vm.items.single.id, reportId);
    expect(vm.lastLoadedAt, stamp);
    state = 'zone';
    await vm.retry();
    expect(vm.zoneRequired, isTrue);
    expect(vm.items, isEmpty);
    state = 'pending';
    final pending = vm.expandArea();
    vm.session.clear();
    last.complete(response(markers([quakeId])));
    await pending;
    expect(vm.lastLoadedAt, isNull);
    expect(vm.hasInteracted || vm.listMode || vm.loading, isFalse);
    expect(vm.items, isEmpty);
    expect(vm.category, isNull);
    expect(vm.radiusOnly && vm.includeReports, isTrue);
  });

  test('zone changes are lazy before browse and supersede in-flight marker data', () async {
    var version = 1;
    var calls = 0;
    final pending = Completer<http.Response>();
    final vm = model((request) async {
      if (request.url.path.endsWith('/me/zone')) return ok({...zoneJson, 'zone_version': version});
      calls++;
      if (calls == 1) return pending.future;
      return response(markers([weatherId], version: version));
    });
    await vm.zone.load();
    expect(calls, 0);
    final old = vm.ensureInitialLoad();
    await Future<void>.delayed(Duration.zero);
    version++;
    await vm.zone.load();
    await Future<void>.delayed(Duration.zero);
    pending.complete(response(markers([quakeId])));
    await old;
    expect(calls, 2);
    expect(vm.meta!.zoneVersion, 2);
    expect(vm.items.single.id, weatherId);
  });

  testWidgets('map, attribution, legend and event detail are accessible at 200%', (tester) async {
    await openBrowse(tester, markers([quakeId, weatherId, reportId], truncated: true));
    expect(find.byType(FlutterMap), findsOneWidget);
    final circle = tester.widget<CircleLayer<Object>>(find.byType(CircleLayer<Object>)).circles.single;
    expect(circle.useRadiusInMeter, isTrue);
    expect(circle.radius, 50000);
    final pins = tester.widget<MarkerLayer>(find.byType(MarkerLayer)).markers;
    expect(pins, hasLength(4));
    expect(pins.every((pin) => pin.width >= 48 && pin.height >= 48), isTrue);
    for (final label in ['SIMULASI — data demo', '© OpenStreetMap contributors',
        'Titik pantau', 'Gempa', 'Cuaca', 'Warga']) {
      expect(find.text(label).hitTestable(), findsOneWidget);
    }
    for (final icon in [Icons.my_location, Icons.waves, Icons.thunderstorm_outlined, Icons.campaign_outlined]) {
      expect(find.byIcon(icon), findsWidgets);
    }
    expect(find.text('Hasil dibatasi 100. Persempit area/filter.'), findsOneWidget);
    await tapVisible(tester, find.byKey(const ValueKey('pin-$quakeId')));
    expect(find.text('BMKG — Gempa'), findsOneWidget);
    expect(find.text('SIMULASI'), findsOneWidget);
    await tapVisible(tester, find.text('Lihat Detail Bencana'));
    final screen = find.byType(EventDetailScreen);
    expect(tester.widget<EventDetailScreen>(screen).eventId, quakeId);
    expect(GoRouter.of(tester.element(screen)).state.uri.path, '/events/$quakeId');
    await closeApp(tester);
  });

  testWidgets('CAP explains its point and offline list opens the citizen summary locally', (tester) async {
    final requests = await openBrowse(tester, markers([weatherId, reportId]), broken: true);
    expect(find.text('Peta dasar tidak tersedia. Daftar dan koordinat tetap dapat digunakan.'), findsOneWidget);
    await tapVisible(tester, find.byKey(const ValueKey('pin-$weatherId')));
    expect(find.textContaining('Titik representatif area (bukan pusat bahaya)'), findsOneWidget);
    Navigator.of(tester.element(find.text('Lihat Detail Bencana'))).pop();
    await tester.pumpAndSettle();
    await tapVisible(tester, find.text('Tampilkan daftar hasil'));
    final reportTile = find.byKey(const ValueKey(reportId));
    await tester.scrollUntilVisible(
      reportTile, 120,
      scrollable: find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)),
    );
    await tester.pumpAndSettle();
    await tapVisible(tester, reportTile);
    final sheet = find.byType(BottomSheet);
    expect(find.descendant(of: sheet, matching: find.text('Warga — ditinjau admin aplikasi')), findsOneWidget);
    expect(find.descendant(of: sheet, matching: find.text('Banjir')), findsOneWidget);
    expect(find.text('Lihat laporan penuh'), findsOneWidget);
    expect(find.text('Detail Bencana'), findsNothing);
    expect(requests.where((uri) => uri.path.contains('/reports/')), isEmpty);
    await closeApp(tester);
  });

  testWidgets('empty results retain the zone and can expand the map or open Feed Semua', (tester) async {
    final requests = await openBrowse(tester, markers([]));
    expect(find.byType(CircleLayer<Object>), findsOneWidget);
    expect(find.text('Belum ada marker sesuai area/filter'), findsOneWidget);
    await tapVisible(tester, find.text('Perluas area'));
    final mapRequest = requests.lastWhere((uri) => uri.path.endsWith('/map/markers'));
    expect(mapRequest.queryParameters['radius_only'], 'false');
    await tapVisible(tester, find.text('Feed Semua'));
    expect(find.byType(MapScreen), findsNothing);
    expect(requests.lastWhere((uri) => uri.path.endsWith('/events')).queryParameters['radius_only'], 'false');
    await closeApp(tester);
  });
}
