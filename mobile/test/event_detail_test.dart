import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:siaga_bencana/app.dart';
import 'package:siaga_bencana/core/session/session_coordinator.dart';
import 'package:siaga_bencana/core/network/api_client.dart';
import 'package:siaga_bencana/features/event_detail/event_detail_screen.dart';
import 'package:siaga_bencana/features/event_detail/event_detail_view_model.dart';
import 'package:siaga_bencana/features/events/event_dto.dart';
import 'package:siaga_bencana/features/events/event_repository.dart';
import 'package:siaga_bencana/features/zone/zone_repository.dart';
import 'package:siaga_bencana/features/zone/zone_view_model.dart';

import 'event_detail_fixtures.dart';
import 'events_feed_test.dart' show failure, response;
import 'widget_test.dart'
    show base, emptyFeed, FakeLocationService, ok, signedIn, TestTileProvider, zoneJson;

final _parse = EventDetailEnvelopeDto.fromJson;

EventDetailViewModel _model(Future<http.Response> Function(http.Request) handler) {
  final session = signedIn();
  final api = ApiClient(client: MockClient(handler), baseUrl: base, session: session);
  final zone = ZoneViewModel(ZoneRepository(api), session, FakeLocationService());
  final vm = EventDetailViewModel(EventRepository(api), session, zone);
  addTearDown(() {
    vm.dispose();
    zone.dispose();
    api.close();
    session.dispose();
  });
  return vm;
}

Future<List<Uri>> _open(
  WidgetTester tester,
  String id,
  http.Response Function(String) detail, {
  bool broken = false,
}) async {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final session = signedIn();
  addTearDown(session.dispose);
  final calls = <Uri>[];
  await tester.pumpWidget(
    SiagaApp(
      initialLocation: '/events/$id',
      session: session,
      baseUrl: base,
      textScaler: const TextScaler.linear(2),
      tileProvider: TestTileProvider(broken: broken),
      client: MockClient((request) async {
        final path = request.url.path;
        calls.add(request.url);
        if (path.startsWith('/api/v1/events/')) {
          expect(request.headers['Authorization'], 'Bearer memory-token');
          return detail(request.url.pathSegments.last);
        }
        if (path.endsWith('/me/zone')) {
          return ok({...zoneJson, 'latitude': 0, 'longitude': 179.9, 'radius_km': 25});
        }
        if (path.endsWith('/events')) return emptyFeed();
        if (path.endsWith('/health')) return ok({'status': 'ok'});
        fail('Unexpected API path $path');
      }),
    ),
  );
  await tester.pumpAndSettle();
  return calls;
}

Future<void> _reveal(WidgetTester tester, Finder target, {double delta = 300}) async {
  await tester.scrollUntilVisible(target, delta, scrollable: find.byType(Scrollable).first);
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, String text, {double delta = 300}) async {
  final target = find.text(text);
  await _reveal(tester, target, delta: delta);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> _close(WidgetTester tester) async {
  final session = tester.element(find.byType(Scaffold).first).read<SessionCoordinator>();
  await tester.pumpWidget(const SizedBox.shrink());
  session.clear();
  expect(tester.takeException(), isNull);
}

void main() {
  test('quake preserves source attributes, server rounding and missing data', () {
    final data = quakeDetail();
    final event = _parse(data).data;
    expect(event.priority.priorityScore, 74.25);
    expect(event.priority.priorityDisplay, '74.3');
    expect(event.earthquake!.magnitude, 5);
    expect(event.earthquake!.potential, potential);
    expect(event.earthquake!.shakemapUrl, startsWith('https:'));
    expect(event.firstSeenAt.isUtc && event.lastSeenAt.isUtc, isTrue);
    for (final key in ['magnitude', 'potential', 'felt', 'shakemap_url']) {
      data['data']['earthquake'][key] = null;
    }
    final missing = _parse(data).data.earthquake!;
    expect([
      missing.magnitude,
      missing.potential,
      missing.felt,
      missing.shakemapUrl,
    ], everyElement(isNull));
  });

  test('radar consumes the server distance and inclusive radius decision unchanged', () {
    final json = quakeDetail();
    final priority = json['data']['priority'] as DetailJson;
    final reason = priority['priority_reasons'][0] as DetailJson;
    for (final (km, inside) in [
      (22.239016, true),
      (25.0, true),
      (25.000001, true),
      (25.000002, false),
    ]) {
      reason['values'] = {'radius_km': 25, 'distance_km': km};
      priority.addAll({'within_radius': inside, 'match_distance_km': km});
      final d = _parse(json).data;
      expect((d.latitude, d.longitude), (0, -179.9));
      expect(d.priority.priorityReasons.first.values['radius_km'], 25);
      expect((d.priority.matchDistanceKm, d.priority.withinRadius), (km, inside));
    }
  });

  test('CAP radar matrix retains server labels, sorted rings and references', () {
    for (final (method, km, within, severity, status, label) in [
      ('inside_polygon', 0.0, true, 'Severe', 'active', 'high'),
      ('near_polygon_sample', 12.5, true, 'Moderate', 'active', 'attention'),
      ('near_polygon_sample', 120.0, false, 'Severe', 'active', 'unavailable'),
      ('no_geometry', null, null, 'Unknown', 'incomplete', 'unavailable'),
    ]) {
      final d = _parse(
        weatherDetail(
          method: method,
          distance: km,
          within: within,
          severity: severity,
          status: status,
          label: label,
        ),
      ).data;
      final p = d.priority;
      expect(
        (
          p.matchMethod,
          p.matchDistanceKm,
          p.withinRadius,
          d.cap!.severity,
          d.lifecycleStatus,
          p.priorityLabel,
        ),
        (method, km, within, severity, status, label),
      );
      expect(p.priorityDisplay, isNull);
      expect(p.priorityScore, isNull);
      expect(d.areas.map((a) => a.position), [1, 2]);
      expect(d.references.map((r) => r.referencedEventId), [quakeKey, null]);
      expect(d.areas.last.polygons.single.geometryValid, isFalse);
      if (method != 'no_geometry') {
        final ring = d.areas.first.polygons.single;
        expect(ring.crossesAntimeridian, isTrue);
        expect(ring.vertices.map((v) => v.longitude), [179, -179, -179, 179, 179]);
        expect(ring.vertices.map((v) => v.sequence), [1, 2, 3, 4, 5]);
      }
    }
  });

  test('rejects contradictory categories, invalid coordinates, versions and geometry', () {
    for (final mutate in <void Function(DetailJson)>[
      (j) => j['data']['category'] = 'earthquake',
      (j) => j['data']['earthquake'] = quakeDetail()['data']['earthquake'],
      (j) => j['data']['latitude'] = 91,
      (j) => j['data']['longitude'] = double.nan,
      (j) => j['data']['content_version'] = 0,
      (j) => j['meta']['zone_version'] = 0,
      (j) => j['data']['priority']['priority_label'] = 'other',
      (j) => j['data']['areas'][0]['polygons'][0]['west'] = 179,
      (j) => j['data']['areas'][1]['polygons'][0]['vertices'] = <Object>[],
      (j) => j['data']['areas'][1]['polygons'][0]['vertices'][0]['longitude'] = 181,
    ]) {
      final json = weatherDetail();
      mutate(json);
      expect(() => _parse(json), throwsFormatException);
    }
  });

  test('repository validates event ID before sending HTTP', () async {
    final vm = _model((_) async => fail('Unexpected request'));
    for (final id in ['', '  ', 'a/b', 'a?b', 'a#b']) {
      await expectLater(vm.repository.fetchEventDetail(id), throwsArgumentError);
    }
  });

  test('refresh retains detail on failure, switching IDs clears old state', () async {
    final pending = Completer<http.Response>();
    var offline = false;
    final vm = _model((request) async {
      if (request.url.path.endsWith(weatherKey)) return pending.future;
      if (offline) throw http.ClientException('offline');
      return response(quakeDetail());
    });
    await vm.load(quakeKey);
    final stamp = vm.lastLoadedAt;
    final original = vm.detail;
    expect(original!.id, quakeKey);
    expect(stamp, isNotNull);
    offline = true;
    final refresh = vm.refresh();
    expect(vm.refreshing, isTrue);
    await refresh;
    expect(vm.error, isNotNull);
    expect(vm.lastLoadedAt, stamp);
    expect(vm.detail, same(original));
    final load = vm.load(weatherKey);
    expect(vm.currentEventId, weatherKey);
    expect([vm.detail, vm.error, vm.meta, vm.lastLoadedAt], everyElement(isNull));
    expect(vm.initialLoading, isTrue);
    pending.complete(response(weatherDetail()));
    await load;
    expect(vm.detail!.id, weatherKey);
    expect(vm.initialLoading || vm.refreshing, isFalse);
  });

  test('a superseded event request cannot overwrite its replacement', () async {
    final pending = Completer<http.Response>();
    final vm = _model(
      (request) async =>
          request.url.path.endsWith(quakeKey) ? pending.future : response(weatherDetail()),
    );
    final first = vm.load(quakeKey);
    await vm.load(weatherKey);
    pending.complete(failure('RESOURCE_NOT_FOUND', 404));
    await first;
    expect(vm.detail!.id, weatherKey);
    expect(vm.notFound, isFalse);
    expect(vm.error, isNull);
  });

  test('late detail after logout cannot restore private data', () async {
    final pending = Completer<http.Response>();
    final vm = _model((_) => pending.future);
    final load = vm.load(quakeKey);
    vm.session.clear();
    pending.complete(response(quakeDetail()));
    await load;
    expect([
      vm.currentEventId,
      vm.detail,
      vm.meta,
      vm.lastLoadedAt,
      vm.error,
    ], everyElement(isNull));
    expect(vm.refreshing || vm.initialLoading || vm.notFound || vm.zoneRequired, isFalse);
  });

  test('zone change reloads and rejects both late and obsolete zone responses', () async {
    final pending = Completer<http.Response>();
    var version = 1;
    var calls = 0;
    final vm = _model((r) async {
      if (r.url.path.endsWith('/me/zone')) return ok({...zoneJson, 'zone_version': version});
      calls++;
      if (calls == 1) return pending.future;
      return response(quakeDetail(version: calls == 2 ? 2 : 1));
    });
    await vm.zone.load();
    final first = vm.load(quakeKey);
    await Future<void>.delayed(Duration.zero);
    version = 2;
    await vm.zone.load();
    await Future<void>.delayed(Duration.zero);
    expect(vm.meta!.zoneVersion, 2);
    pending.complete(response(quakeDetail()));
    await first;
    final accepted = vm.detail;
    await vm.refresh();
    expect(calls, 3);
    expect(vm.meta!.zoneVersion, 2);
    expect(vm.detail, same(accepted));
    expect(vm.error, isNotNull);
  });

  test('404 and 409 expose separate recovery states', () async {
    final vm = _model(
      (r) async => r.url.path.endsWith(quakeKey)
          ? failure('RESOURCE_NOT_FOUND', 404)
          : failure('ZONE_REQUIRED', 409),
    );
    await vm.load(quakeKey);
    expect(vm.notFound, isTrue);
    await vm.load(weatherKey);
    expect(vm.notFound, isFalse);
    expect(vm.zoneRequired, isTrue);
  });

  testWidgets('quake at 200% shows server priority, source and related report action', (
    tester,
  ) async {
    final json = quakeDetail();
    json['data']['earthquake']['shakemap_url'] = null;
    final calls = await _open(tester, quakeKey, (_) => response(json));
    await _reveal(tester, find.text('Gempa uji radar'));
    await _reveal(tester, find.text('Prioritas 74.3 — Tinggi'));
    await _tap(tester, 'Mengapa?');
    await _reveal(tester, find.text(distanceReason));
    await _reveal(tester, find.text('Potensi'));
    expect(find.text(potential), findsOneWidget);
    await _reveal(tester, find.text('Tidak tersedia dari sumber'));
    await _reveal(tester, find.byType(FlutterMap));
    await _reveal(tester, find.text('© OpenStreetMap contributors'));
    final router = GoRouter.of(tester.element(find.byType(EventDetailScreen)));
    await _tap(tester, 'Buka sumber resmi');
    expect(find.text(officialUrl), findsOneWidget);
    await tester.tap(find.text('Tutup'));
    await tester.pumpAndSettle();
    await _tap(tester, 'Laporkan kondisi terkait');
    expect(router.state.uri.toString(), '/reports?event_id=$quakeKey');
    expect(find.text('Terkait event: $quakeKey'), findsOneWidget);
    expect(calls.where((uri) => uri.path.endsWith('/reports')), isEmpty);
    await _close(tester);
  });

  testWidgets('CAP at 200% keeps crossing polygon and reference usable when tiles fail', (
    tester,
  ) async {
    final quake = quakeDetail();
    quake['data']['earthquake']['shakemap_url'] = null;
    await _open(
      tester,
      weatherKey,
      (id) => response(id == quakeKey ? quake : weatherDetail()),
      broken: true,
    );
    await _reveal(tester, find.text('Titik pantau berada dalam area'));
    await _reveal(tester, find.byType(FlutterMap));
    final layer = tester.widget<PolygonLayer<Object>>(find.byType(PolygonLayer<Object>));
    expect(layer.polygons, hasLength(1));
    final points = layer.polygons.single.points;
    expect(points, hasLength(5));
    expect(points.map((v) => v.longitude), [179, -179, -179, 179, 179]);
    expect(layer.drawInSingleWorld || layer.polygonCulling, isFalse);
    await _reveal(
      tester,
      find.text('Peta dasar tidak tersedia. Daftar dan koordinat tetap dapat digunakan.'),
    );
    await _tap(tester, 'Lihat event rujukan', delta: -300);
    expect(
      GoRouter.of(tester.element(find.byType(EventDetailScreen))).state.uri.path,
      '/events/$quakeKey',
    );
    await _reveal(tester, find.text('Gempa uji radar'));
    await tester.tap(find.byTooltip('Kembali'));
    await tester.pumpAndSettle();
    await _reveal(tester, find.text('Peringatan Pasifik'), delta: -300);
    await _close(tester);
  });

  testWidgets('nearby CAP keeps its location estimate visible after a failed refresh', (
    tester,
  ) async {
    var offline = false;
    final near = weatherDetail(
      method: 'near_polygon_sample',
      distance: 12.5,
      severity: 'Moderate',
      label: 'attention',
    );
    await _open(
      tester,
      weatherKey,
      (_) => offline ? failure('NETWORK_ERROR', 503) : response(near),
    );
    offline = true;
    await tester.tap(find.byTooltip('Muat ulang'));
    await tester.pumpAndSettle();
    await _reveal(tester, find.textContaining('Data terakhir dimuat'));
    expect(find.text('Coba Lagi'), findsOneWidget);
    await _reveal(tester, find.text('Peringatan Pasifik'));
    await _reveal(tester, find.text('Dekat area peringatan — perkiraan centroid/vertex'));
    await _close(tester);
  });

  testWidgets('expired CAP without geometry uses text and recovers from a missing reference', (
    tester,
  ) async {
    final expired = weatherDetail(
      method: 'no_geometry',
      distance: null,
      within: null,
      status: 'expired',
      severity: 'Unknown',
      label: 'unavailable',
    );
    await _open(
      tester,
      weatherKey,
      (id) => id == weatherKey ? response(expired) : failure('RESOURCE_NOT_FOUND', 404),
    );
    await _reveal(tester, find.text('Kedaluwarsa'));
    await _reveal(tester, find.text('Kecocokan lokasi belum tersedia'));
    await _reveal(tester, find.text('Peta mini'));
    expect(find.byType(FlutterMap), findsNothing);
    await _reveal(tester, find.text('Belum ada laporan warga ditinjau yang terkait'));
    await _tap(tester, 'Lihat event rujukan', delta: -300);
    expect(find.text('Informasi tidak tersedia'), findsOneWidget);
    await _close(tester);
  });
}
