import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:provider/provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:siaga_bencana/app.dart';
import 'package:siaga_bencana/core/network/api_client.dart';
import 'package:siaga_bencana/core/network/api_envelope.dart';
import 'package:siaga_bencana/core/routing/app_router.dart';
import 'package:siaga_bencana/core/session/session_coordinator.dart';
import 'package:siaga_bencana/core/theme/app_theme.dart';
import 'package:siaga_bencana/features/auth/account_screen.dart';
import 'package:siaga_bencana/features/auth/auth_dto.dart';
import 'package:siaga_bencana/features/zone/location_service.dart';
import 'package:siaga_bencana/features/zone/zone_dto.dart';
import 'package:siaga_bencana/features/zone/zone_repository.dart';
import 'package:siaga_bencana/features/zone/zone_view_model.dart';

import 'event_detail_fixtures.dart';

const userJson = <String, dynamic>{
  'id': '10000000-0000-4000-8000-000000000001',
  'email': 'warga@example.test',
  'display_name': 'Warga',
  'role': 'citizen',
  'has_zone': false,
};
const meta = <String, dynamic>{
  'server_time': '2026-11-17T00:00:00Z',
  'mode': 'local_live',
  'is_simulated': false,
};
final base = Uri.parse('http://localhost:8000/api/v1');
Map<String, dynamic> authJson({bool hasZone = false}) => {
  'access_token': 'memory-token',
  'token_type': 'bearer',
  'expires_in': 3600,
  'expires_at': DateTime.now()
      .toUtc()
      .add(const Duration(hours: 1))
      .toIso8601String(),
  'user': {...userJson, 'has_zone': hasZone},
};
http.Response ok(Object? data, {int status = 200}) => http.Response(
  jsonEncode({'data': data, 'meta': meta}),
  status,
  headers: {'content-type': 'application/json'},
);
http.Response emptyFeed() => http.Response(jsonEncode({
  'items': <Object>[],
  'page': {'limit': 20, 'offset': 0, 'next_offset': null, 'has_more': false},
  'meta': {...meta, 'zone_version': 1, 'sources': [
    for (final source in ['BMKG_TEWS', 'BMKG_NOWCAST'])
      {'source': source, 'state': 'unavailable', 'last_success_at': null, 'last_attempt_at': null},
  ]},
}), 200);

SessionCoordinator signedIn({bool zone = true}) {
  final session = SessionCoordinator();
  final auth = AuthData.fromJson(authJson(hasZone: zone));
  session.establish(auth);
  session.confirm(auth.user, session.generation);
  return session;
}

const zoneJson = <String, dynamic>{
  'id': '20000000-0000-4000-8000-000000000001',
  'latitude': -7.25, 'longitude': 112.75, 'radius_km': 50,
  'notify_earthquake': true, 'notify_weather': true, 'zone_version': 1,
  'alert_eligible_since': '2026-11-18T00:00:00Z',
  'updated_at': '2026-11-18T00:00:00Z',
};

class FakeLocationService implements LocationService {
  FakeLocationService({this.failure, this.pending});
  final LocationFailure? failure;
  final Future<ZoneLocation>? pending;
  int calls = 0;
  int settingsCalls = 0;
  @override
  Future<ZoneLocation> locateOnce() async {
    calls++;
    if (failure != null) throw failure!;
    if (pending != null) return pending!;
    return const ZoneLocation(-7.25, 112.75);
  }
  @override
  Future<bool> openAppSettings() async { settingsCalls++; return true; }
}

class TestTileProvider extends TileProvider {
  TestTileProvider({this.broken = false});
  final bool broken;
  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) =>
      MemoryImage(base64Decode(broken ? '' :
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNgYGBgAAAABQABpfZFQAAAAABJRU5ErkJggg=='));
}

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  test('nullable envelope and exact canonical zone DTO contract', () {
    expect(ApiEnvelope.fromJson({'data': null, 'meta': meta}).data, isNull);
    expect(() => ApiEnvelope.fromJson({'data': null, 'meta': meta}).requiredData,
      throwsA(isA<ApiErrorEnvelope>()));
    final zone = ZoneDto.fromJson(zoneJson);
    expect(zone.id, zoneJson['id']);
    expect(zone.zoneVersion, 1);
    expect(zone.radiusKm, 50);
    expect(zone.notifyEarthquake && zone.notifyWeather, isTrue);
    expect(zone.alertEligibleSince.isUtc && zone.updatedAt.isUtc, isTrue);
    const request = ZoneUpdateRequest(latitude: -0.0, longitude: 180);
    final json = request.toJson();
    expect(json, {'latitude': 0.0, 'longitude': -180.0, 'radius_km': 50,
      'notify_earthquake': true, 'notify_weather': true});
    expect((json['latitude'] as double).isNegative, false);
    expect((const ZoneUpdateRequest(latitude: 0, longitude: -0.0)
        .toJson()['longitude'] as double).isNegative, false);
    for (final lat in [double.nan, double.infinity, -91.0, 91.0]) {
      expect(() => ZoneUpdateRequest(latitude: lat, longitude: 0).toJson(),
        throwsFormatException);
    }
    for (final lon in [double.nan, double.infinity, -181.0, 181.0]) {
      expect(() => ZoneUpdateRequest(latitude: 0, longitude: lon).toJson(),
        throwsFormatException);
    }
    expect(() => ZoneDto.fromJson({...zoneJson, 'zone_version': 0}), throwsFormatException);
    expect(() => ZoneDto.fromJson({...zoneJson, 'longitude': 180}), throwsFormatException);
  });

  for (final operation in ['fetch', 'save', 'gps']) {
    test('late $operation cannot restore drafts or zone after session changes', () async {
      final session = signedIn(zone: false);
      final httpResult = Completer<http.Response>();
      final gpsResult = Completer<ZoneLocation>();
      final api = ApiClient(baseUrl: base, session: session,
        client: MockClient((_) => httpResult.future));
      final vm = ZoneViewModel(ZoneRepository(api), session,
        FakeLocationService(pending: gpsResult.future));
      addTearDown(() { vm.dispose(); api.close(); session.dispose(); });
      vm.selectPoint(-7, 112);
      final generation = session.generation;
      final Future<void> pending;
      if (operation == 'fetch') {
        pending = vm.load();
      } else if (operation == 'save') {
        pending = vm.save().then<void>((_) {});
      } else {
        pending = vm.locateOnce();
      }
      await Future<void>.delayed(Duration.zero);
      session.clear();
      session.establish(AuthData.fromJson(authJson()));
      // Remain unverified so the new session has not fetched its own zone yet.
      expect(session.markZoneSaved(generation), false);
      httpResult.complete(ok(zoneJson));
      gpsResult.complete(const ZoneLocation(10, 20));
      await pending;
      expect(vm.savedZone, isNull);
      expect(vm.latitude, isNull);
      expect(vm.longitude, isNull);
      expect(vm.radiusKm, 50);
      expect(vm.loading || vm.saving || vm.locating, false);
      expect(session.user!.hasZone, false);
      expect(vm.error, isNull);
    });
  }

  test('zone network errors retain draft, duplicate save is ignored, retry uses server snapshot', () async {
    final session = signedIn(zone: false);
    final response = Completer<http.Response>();
    var putCount = 0;
    var fail = true;
    final api = ApiClient(baseUrl: base, session: session,
      client: MockClient((request) async {
        if (request.method == 'GET') return ok(null);
        putCount++;
        if (fail) return response.future;
        return ok({...zoneJson, 'longitude': -180.0});
      }));
    final vm = ZoneViewModel(ZoneRepository(api), session, FakeLocationService());
    addTearDown(() { vm.dispose(); api.close(); session.dispose(); });
    await vm.load();
    vm.selectPoint(-7.25, 180);
    final pending = vm.save();
    expect(await vm.save(), false);
    response.complete(http.Response(jsonEncode({
      'code': 'SERVICE_UNAVAILABLE', 'message': 'Coba lagi.',
      'details': null, 'request_id': 'test',
    }), 503));
    expect(await pending, false);
    expect(putCount, 1);
    expect(vm.longitude, -180);
    expect(vm.savedZone, isNull);
    expect(session.user!.hasZone, false);
    expect(vm.error, 'Coba lagi.');
    fail = false;
    expect(await vm.save(), true);
    expect(vm.savedZone!.longitude, -180);
    expect(session.user!.hasZone, true);
    expect(vm.error, isNull);
  });

  test('GPS timeout preserves manual selection and enables retry', () async {
    final session = signedIn(zone: false);
    final result = Completer<ZoneLocation>();
    final api = ApiClient(baseUrl: base, session: session,
      client: MockClient((_) async => ok(null)));
    final vm = ZoneViewModel(ZoneRepository(api), session,
      FakeLocationService(pending: result.future));
    addTearDown(() { vm.dispose(); api.close(); session.dispose(); });
    vm.selectPoint(0, 0);
    final pending = vm.locateOnce();
    result.completeError(TimeoutException('GPS timeout'));
    await pending;
    expect(vm.gpsMessage, contains('10 detik'));
    expect(vm.locating, false);
    expect(vm.canSave, true);
    expect(vm.latitude, 0);
  });

  testWidgets('GPS once -> authenticated PUT -> home at 360px / 200%', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final session = signedIn(zone: false);
    addTearDown(session.dispose);
    final location = FakeLocationService();
    final requests = <String>[];
    await tester.pumpWidget(SiagaApp(
      session: session, baseUrl: base, locationService: location,
      textScaler: const TextScaler.linear(2),
      client: MockClient((request) async {
        requests.add('${request.method} ${request.url.path}');
        if (request.url.path.endsWith('/health')) return ok({'status': 'ok'});
        if (request.method == 'GET' && request.url.path == '/api/v1/events') return emptyFeed();
        expect(request.url.path, '/api/v1/me/zone');
        expect(request.headers['Authorization'], 'Bearer memory-token');
        if (request.method == 'GET') return ok(null);
        expect(jsonDecode(request.body), const ZoneUpdateRequest(
          latitude: -7.25, longitude: 112.75).toJson());
        return ok(zoneJson);
      }),
    ));
    await tester.pumpAndSettle();
    expect(location.calls, 0);
    expect(tester.widget<FilledButton>(find.byKey(const Key('save-zone'))).onPressed, isNull);
    await tapVisible(tester, find.text('Gunakan lokasi saya sekali'));
    expect(location.calls, 1);
    expect(find.textContaining('Lintang: -7.25'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tapVisible(tester, find.byKey(const Key('save-zone')));
    expect(session.canNavigate, true);
    expect(GoRouter.of(tester.element(find.byType(NavigationBar)))
        .routeInformationProvider.value.uri.path, '/home');
    expect(requests.where((value) => value.startsWith('PUT')), hasLength(1));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    session.clear();
  });

  for (final permanentlyDenied in [false, true]) {
    testWidgets('GPS denied (permanent=$permanentlyDenied) -> manual picker, no PUT', (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final session = signedIn(zone: false);
      addTearDown(session.dispose);
      final location = FakeLocationService(failure: LocationFailure(
        'Izin lokasi ditolak. Pilih titik manual.', canOpenSettings: permanentlyDenied));
      final requests = <String>[];
      await tester.pumpWidget(SiagaApp(
        session: session, baseUrl: base, locationService: location,
        tileProvider: TestTileProvider(), textScaler: const TextScaler.linear(2),
        client: MockClient((request) async {
          requests.add('${request.method} ${request.url.path}');
          return request.url.path.endsWith('/health') ? ok({'status': 'ok'}) : ok(null);
        }),
      ));
      await tester.pumpAndSettle();
      final vm = tester.element(find.byType(AccountScreen)).read<ZoneViewModel>();
      await tapVisible(tester, find.text('Gunakan lokasi saya sekali'));
      expect(find.text('Izin lokasi ditolak. Pilih titik manual.'), findsOneWidget);
      if (permanentlyDenied) {
        await tapVisible(tester, find.text('Buka Pengaturan'));
        expect(location.settingsCalls, 1);
      }
      await tapVisible(tester, find.text('Pilih titik di peta / manual'));
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.text('\u00a9 OpenStreetMap contributors'), findsOneWidget);
      final map = find.byKey(const Key('zone-map'));
      await tester.ensureVisible(map);
      await tester.tapAt(tester.getCenter(map));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(find.byKey(const Key('zone-latitude')))
          .controller!.text, isNotEmpty);
      expect(vm.latitude, isNull, reason: 'Picker is transactional until confirmation');
      for (final invalid in ['NaN', 'Infinity', '91', '-91']) {
        await tester.enterText(find.byKey(const Key('zone-latitude')), invalid);
        await tester.enterText(find.byKey(const Key('zone-longitude')), '112');
        await tester.pumpAndSettle();
        expect(tester.widget<FilledButton>(find.byKey(const Key('confirm-point'))).onPressed, isNull);
      }
      await tester.enterText(find.byKey(const Key('zone-latitude')), '-7.25');
      for (final invalid in ['NaN', 'Infinity', '181', '-181']) {
        await tester.enterText(find.byKey(const Key('zone-longitude')), invalid);
        await tester.pumpAndSettle();
        expect(tester.widget<FilledButton>(find.byKey(const Key('confirm-point'))).onPressed, isNull);
      }
      await tester.enterText(find.byKey(const Key('zone-longitude')), '180');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tapVisible(tester, find.byKey(const Key('confirm-point')));
      expect(vm.latitude, -7.25);
      expect(vm.longitude, -180);
      expect(session.user!.hasZone, false);
      expect(requests.any((value) => value.startsWith('PUT') || value.contains('/map/')), false);
      await tapVisible(tester, find.text('Pilih titik di peta / manual'));
      await tester.enterText(find.byKey(const Key('zone-latitude')), '12');
      await tapVisible(tester, find.text('Batal'));
      expect(vm.latitude, -7.25);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      session.clear();
    });
  }

  testWidgets('profile edit preloads saved zone and returns to profile after save', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final session = signedIn();
    addTearDown(session.dispose);
    Map<String, dynamic>? body;
    await tester.pumpWidget(SiagaApp(
      session: session, baseUrl: base, initialLocation: '/profile',
      textScaler: const TextScaler.linear(2),
      client: MockClient((request) async {
        if (request.url.path.endsWith('/health')) return ok({'status': 'ok'});
        if (request.method == 'PUT') {
          body = jsonDecode(request.body) as Map<String, dynamic>;
          return ok({...zoneJson, ...body!, 'zone_version': 2});
        }
        return ok(zoneJson);
      }),
    ));
    await tester.pumpAndSettle();
    expect(find.text('warga@example.test'), findsOneWidget);
    expect(find.text('Radius: 50 km'), findsOneWidget);
    await tapVisible(tester, find.text('Ubah Zona Pantau'));
    expect(find.byType(AccountScreen), findsOneWidget);
    expect(find.text('Kembali'), findsOneWidget);
    await tapVisible(tester, find.text('25 km'));
    await tapVisible(tester, find.text('Cuaca Ekstrem'));
    await tapVisible(tester, find.byKey(const Key('save-zone')));
    expect(body!['radius_km'], 25);
    expect(body!['notify_weather'], false);
    expect(find.text('Radius: 25 km'), findsOneWidget);
    expect(find.text('Cuaca Ekstrem: Nonaktif'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    session.clear();
  });

  testWidgets('tile failure keeps manual coordinates usable', (tester) async {
    final session = signedIn(zone: false);
    addTearDown(session.dispose);
    await tester.pumpWidget(SiagaApp(
      session: session, baseUrl: base, initialLocation: '/map?mode=pick_zone',
      tileProvider: TestTileProvider(broken: true),
      client: MockClient((request) async => request.url.path.endsWith('/health')
          ? ok({'status': 'ok'}) : ok(null)),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Peta dasar tidak tersedia. Daftar dan koordinat tetap dapat digunakan.'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('zone-latitude')), '0');
    await tester.enterText(find.byKey(const Key('zone-longitude')), '0');
    await tester.pumpAndSettle();
    await tapVisible(tester, find.byKey(const Key('confirm-point')));
    expect(find.textContaining('Lintang: 0.0'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    session.clear();
  });

  test('manual DTOs preserve password, normalize identity, and reject invalid roles', () {
    final user = UserDto.fromJson(userJson);
    expect(user.toJson(), userJson);
    expect(AuthData.fromJson(authJson()).expiresAt.isUtc, isTrue);
    const request = RegisterRequest(
      ' WARGA@EXAMPLE.TEST ',
      '  password  ',
      ' Warga ',
    );
    expect(request.toJson(), {
      'email': 'warga@example.test',
      'password': '  password  ',
      'display_name': 'Warga',
    });
    expect(
      () => UserDto.fromJson({...userJson, 'role': 'root'}),
      throwsFormatException,
    );
    expect(
      () => AuthData.fromJson({...authJson(), 'token_type': 'basic'}),
      throwsFormatException,
    );
  });

  test(
    'error envelope and simulation metadata parse without losing fields',
    () {
      const json = <String, dynamic>{
        'code': 'VALIDATION_ERROR',
        'message': 'Periksa isian.',
        'details': {
          'fields': [
            {'field': 'email', 'code': 'invalid'},
          ],
        },
        'request_id': 'request-uuid',
      };
      final failure = ApiErrorEnvelope.fromJson(json, statusCode: 422);
      expect(failure.toJson(), json);
      expect(failure.statusCode, 422);
      expect(
        ApiMeta.fromJson({...meta, 'mode': 'simulation', 'is_simulated': true})
            .isSimulated,
        true,
      );
      expect(
        () => ApiMeta.fromJson({...meta, 'mode': 'simulation'}),
        throwsFormatException,
      );
    },
  );

  test(
    '401 clears token and private user data; GET has Bearer and no body',
    () async {
      final session = signedIn();
      addTearDown(session.dispose);
      final client = ApiClient(
        baseUrl: base,
        session: session,
        client: MockClient((request) async {
          expect(request.headers['Authorization'], 'Bearer memory-token');
          expect(request.headers['Accept'], 'application/json');
          expect(request.body, isEmpty);
          return http.Response(
            jsonEncode({
              'code': 'TOKEN_EXPIRED',
              'message': 'Sesi berakhir.',
              'details': null,
              'request_id': 'request-uuid',
            }),
            401,
          );
        }),
      );
      await expectLater(
        client.get('/me', authenticated: true),
        throwsA(isA<ApiErrorEnvelope>()),
      );
      expect(session.token, isNull);
      expect(session.user, isNull);
      expect(session.message, contains('Sesi berakhir'));
    },
  );

  test(
    'late 401 from previous session cannot log out the new account',
    () async {
      final session = signedIn();
      addTearDown(session.dispose);
      final deferred = Completer<http.Response>();
      final client = ApiClient(
        baseUrl: base,
        session: session,
        client: MockClient((_) => deferred.future),
      );
      final pending = client.get('/me', authenticated: true);
      final assertion = expectLater(
        pending,
        throwsA(
          isA<ApiErrorEnvelope>().having(
            (e) => e.code,
            'code',
            'SESSION_CHANGED',
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      session.clear();
      final auth = AuthData.fromJson({
        ...authJson(),
        'access_token': 'new-session-token',
      });
      session.establish(auth);
      session.confirm(auth.user, session.generation);
      deferred.complete(http.Response('{}', 401));
      await assertion;
      expect(session.token, 'new-session-token');
    },
  );

  test(
    'expiry uses UTC wall clock before any authenticated network call',
    () async {
      var now = DateTime.now().toUtc();
      final session = SessionCoordinator(now: () => now);
      addTearDown(session.dispose);
      session.establish(AuthData.fromJson(authJson()));
      now = now.add(const Duration(hours: 2));
      var sent = false;
      final api = ApiClient(
        baseUrl: base,
        session: session,
        client: MockClient((_) async {
          sent = true;
          return ok(userJson);
        }),
      );
      await expectLater(
        api.get('/me', authenticated: true),
        throwsA(isA<ApiErrorEnvelope>()),
      );
      expect(sent, false);
      expect(session.user, isNull);
    },
  );

  test(
    'malformed responses and retry headers become typed API errors',
    () async {
      final session = SessionCoordinator();
      addTearDown(session.dispose);
      var invalid = true;
      final api = ApiClient(
        baseUrl: base,
        session: session,
        client: MockClient(
          (_) async => invalid
              ? http.Response('<html>bad gateway</html>', 502)
              : http.Response(
                  jsonEncode({
                    'code': 'RATE_LIMITED',
                    'message': 'Tunggu.',
                    'details': null,
                    'request_id': 'request-uuid',
                  }),
                  429,
                  headers: {'retry-after': '17'},
                ),
        ),
      );
      await expectLater(
        api.get('/health'),
        throwsA(
          isA<ApiErrorEnvelope>().having(
            (e) => e.code,
            'code',
            'INVALID_RESPONSE',
          ),
        ),
      );
      invalid = false;
      await expectLater(
        api.post('/auth/login', {}),
        throwsA(
          isA<ApiErrorEnvelope>().having((e) => e.retryAfter, 'retryAfter', 17),
        ),
      );
    },
  );

  testWidgets('login UI at 360px / 200% has no overflow and probes health', (
    tester,
  ) async {
    tester.view.reset();
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final paths = <String>[];
    await tester.pumpWidget(
      SiagaApp(
        baseUrl: base,
        textScaler: const TextScaler.linear(2),
        client: MockClient((request) async {
          paths.add(request.url.path);
          return ok({'status': 'ok'});
        }),
      ),
    );
    await tester.pumpAndSettle();
    expect(paths, ['/api/v1/health']);
    expect(find.byType(AccountScreen), findsOneWidget);
    expect(find.textContaining('API terhubung'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.byKey(const Key('submit')));
    await tester.tap(find.byKey(const Key('submit')));
    await tester.pumpAndSettle();
    expect(find.text('Masukkan alamat email yang valid.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final register in [false, true]) {
    testWidgets(
      '${register ? 'register' : 'login'} -> me -> GET zone -> UI-01c',
      (tester) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final paths = <String>[];
        final mock = MockClient((request) async {
          paths.add(request.url.path);
          if (request.url.path.endsWith('/health')) return ok({'status': 'ok'});
          if (request.url.path.endsWith('/me/zone')) return ok(null);
          if (request.url.path.endsWith('/me')) {
            expect(request.headers['Authorization'], 'Bearer memory-token');
            return ok(userJson);
          }
          expect(
            request.url.path,
            '/api/v1/auth/${register ? 'register' : 'login'}',
          );
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['email'], 'warga@example.test');
          expect(body['password'], '  password long  ');
          expect(body.containsKey('role'), false);
          if (register) expect(body['display_name'], 'Warga');
          return ok(authJson(), status: register ? 201 : 200);
        });
        await tester.pumpWidget(
          SiagaApp(
            client: mock,
            baseUrl: base,
            textScaler: const TextScaler.linear(2),
          ),
        );
        await tester.pumpAndSettle();
        if (register) {
          await tester.ensureVisible(find.text('Daftar'));
          await tester.tap(find.text('Daftar'));
          await tester.pumpAndSettle();
          await tester.enterText(find.byKey(const Key('name')), ' Warga ');
        }
        await tester.enterText(
          find.byKey(const Key('email')),
          ' WARGA@EXAMPLE.TEST ',
        );
        await tester.enterText(
          find.byKey(const Key('password')),
          '  password long  ',
        );
        await tester.ensureVisible(find.byKey(const Key('submit')));
        await tester.tap(find.byKey(const Key('submit')));
        await tester.pumpAndSettle();
        expect(find.text('UI-01c • Atur Zona Pantau'), findsOneWidget);
        expect(paths, [
          '/api/v1/health',
          '/api/v1/auth/${register ? 'register' : 'login'}',
          '/api/v1/me',
          '/api/v1/me/zone',
        ]);
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.text('Keluar'));
        await tester.tap(find.text('Keluar'));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('email')), findsOneWidget);
        expect(
          tester
              .widget<TextFormField>(find.byKey(const Key('password')))
              .controller!
              .text,
          isEmpty,
        );
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'six exact routes and guards for logged out / no-zone / authenticated',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final session = SessionCoordinator();
      addTearDown(session.dispose);
      var markerRequests = 0;
      await tester.pumpWidget(
        SiagaApp(
          client: MockClient((request) async {
            if (request.url.path.startsWith('/api/v1/events/')) {
              final detail = quakeDetail(id: request.url.pathSegments.last);
              detail['data']['earthquake']['shakemap_url'] = null;
              return http.Response.bytes(utf8.encode(jsonEncode(detail)), 200);
            }
            if (request.url.path.endsWith('/events')) return emptyFeed();
            if (request.url.path.endsWith('/map/markers')) {
              markerRequests++;
              return http.Response(jsonEncode({
                'items': <Object>[], 'cap': 100, 'truncated': false,
                'meta': {...meta, 'zone_version': 1, 'sources': [
                  for (final source in ['BMKG_TEWS', 'BMKG_NOWCAST'])
                    {'source': source, 'state': 'healthy', 'last_success_at': null, 'last_attempt_at': null},
                ]},
              }), 200);
            }
            return request.url.path.endsWith('/me/zone') ? ok(null) : ok({'status': 'ok'});
          }),
          baseUrl: base,
          session: session,
          initialLocation: '/events/demo-id',
          tileProvider: TestTileProvider(),
          textScaler: const TextScaler.linear(2),
        ),
      );
      await tester.pumpAndSettle();
      final context = tester.element(find.byType(AccountScreen));
      final router = GoRouter.of(context);
      List<String> routePaths(List<RouteBase> routes) => routes
          .expand(
            (route) => [
              if (route is GoRoute) route.path,
              ...routePaths(route.routes),
            ],
          )
          .toList();
      expect(mainRoutes, [
        '/account', '/home', '/map', '/reports', '/profile', '/events/:eventId',
      ]);
      expect(
        routePaths(router.configuration.routes),
        unorderedEquals(mainRoutes),
      );
      expect(router.routeInformationProvider.value.uri.path, '/account');
      final auth = AuthData.fromJson(authJson());
      session.establish(auth);
      session.confirm(auth.user, session.generation);
      await tester.pumpAndSettle();
      router.go('/home');
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/account');
      session.confirm(
        UserDto.fromJson({...userJson, 'has_zone': true}),
        session.generation,
      );
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/events/demo-id');
      for (final path in [
        '/home',
        '/map',
        '/reports',
        '/profile',
        '/events/id-2',
      ]) {
        router.go(path);
        await tester.pumpAndSettle();
        expect(router.routeInformationProvider.value.uri.path, path);
        if (path == '/home') expect(markerRequests, 0);
        if (path == '/map') expect(markerRequests, greaterThan(0));
        if (path == '/reports') {
          expect(find.text('Tulis Laporan'), findsOneWidget);
        }
        if (!path.startsWith('/events/')) {
          expect(find.byType(NavigationBar), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
      }
      session.clear(expired: true);
      await tester.pumpAndSettle();
      expect(find.byType(AccountScreen), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('offline health never invents live mode', (tester) async {
    await tester.pumpWidget(
      SiagaApp(
        baseUrl: base,
        client: MockClient((_) async {
          throw http.ClientException('offline');
        }),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('API tidak terjangkau'), findsOneWidget);
    expect(find.textContaining('API terhubung'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('theme matches locked Page 2 colors', () {
    final theme = appTheme();
    expect(theme.useMaterial3, true);
    expect(theme.colorScheme.primary, const Color(0xFF0F4C5C));
    expect(theme.colorScheme.primaryContainer, const Color(0xFFD8EEF3));
    expect(theme.scaffoldBackgroundColor, const Color(0xFFF8FAFC));
    expect(theme.colorScheme.outline, const Color(0xFFCBD5E1));
    expect(
      theme.filledButtonTheme.style!.minimumSize!.resolve({})!.height,
      greaterThanOrEqualTo(48),
    );
  });
}
