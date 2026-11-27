import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:siaga_bencana/app.dart';
import 'package:siaga_bencana/core/network/api_client.dart';
import 'package:siaga_bencana/core/network/api_envelope.dart';
import 'package:siaga_bencana/core/session/session_coordinator.dart';
import 'package:siaga_bencana/core/session/session_store.dart';
import 'package:siaga_bencana/core/theme/app_theme.dart';
import 'package:siaga_bencana/core/widgets/permission_onboarding_dialog.dart';
import 'package:siaga_bencana/core/widgets/ui_kit.dart';
import 'package:siaga_bencana/features/auth/auth_dto.dart';
import 'package:siaga_bencana/features/home/home_screen.dart';
import 'package:siaga_bencana/features/map/map_dto.dart';
import 'package:siaga_bencana/features/notifications/local_notification_service.dart';
import 'package:siaga_bencana/features/profile/profile_screen.dart';
import 'package:siaga_bencana/features/weather/weather_view_model.dart';
import 'package:siaga_bencana/features/zone/location_service.dart';
import 'package:siaga_bencana/features/zone/zone_dto.dart';
import 'package:siaga_bencana/features/zone/zone_view_model.dart';

import 'events_feed_test.dart' show quakeId;
import 'map_browse_test.dart' show closeApp, marker, markers, openBrowse;
import 'notifications_profile_test.dart' show FakeLocal;
import 'widget_test.dart' show FakeLocationService, TestTileProvider, authJson, base, emptyFeed, ok,
    signedIn, tapVisible, userJson, zoneJson;

const suggestion = {
  'label': 'Surabaya', 'subtitle': 'Jawa Timur', 'source': 'geocoding',
  'latitude': -7.25, 'longitude': 112.75,
};

const weatherJson = {
  'temperature_c': 28.3, 'humidity_percent': 80, 'precipitation_mm': 1,
  'wind_speed_kmh': 9.4, 'weather_code': 3, 'condition_code': 'cloudy',
  'condition_label': 'Berawan', 'observed_at': '2026-11-26T10:00:00Z',
  'source': 'open_meteo', 'is_cached': false,
};

class _LocationPermissions extends FakeLocationService implements LocationPermissionRequester {
  int requests = 0;
  @override
  Future<bool> requestLocationPermission() async {
    requests++;
    return false;
  }
}

void main() {
  for (final method in ['GET', 'POST', 'PUT']) {
    test('$method retries only a GET transport failure', () async {
      final session = signedIn();
      var calls = 0;
      final api = ApiClient(baseUrl: base, session: session, client: MockClient((_) async {
        if (++calls == 1) throw http.ClientException('disconnected');
        return ok({'ok': true});
      }));
      addTearDown(() { api.close(); session.dispose(); });
      if (method == 'GET') {
        expect((await api.get('/health')).requiredData['ok'], true);
        expect(calls, 2);
      } else {
        final request = method == 'POST' ? api.post('/auth/login', {}) : api.put('/me/zone', {});
        await expectLater(request, throwsA(isA<ApiErrorEnvelope>().having(
          (e) => e.code, 'code', 'NETWORK_ERROR')));
        expect(calls, 1);
      }
    });
  }

  test('an aborted GET never starts a retry', () async {
    final session = SessionCoordinator();
    final abort = Completer<void>();
    var calls = 0;
    final api = ApiClient(baseUrl: base, session: session, client: MockClient((_) async {
      calls++;
      abort.complete();
      throw http.ClientException('aborted');
    }));
    addTearDown(() { api.close(); session.dispose(); });
    await expectLater(api.getJson('/health', abortTrigger: abort.future),
      throwsA(isA<ApiErrorEnvelope>().having((e) => e.code, 'code', 'CANCELLED')));
    expect(calls, 1);
  });

  test('suggestions require numeric coordinates within bounds', () {
    expect(LocationSuggestionDto.fromJson(suggestion).longitude, 112.75);
    for (final lat in ['-7', 91, double.nan]) {
      expect(() => LocationSuggestionDto.fromJson({...suggestion, 'latitude': lat}),
        throwsFormatException);
    }
    expect(() => LocationSuggestionDto.fromJson({...suggestion, 'longitude': 181}),
      throwsFormatException);
  });

  testWidgets('search result fills the zone draft', (tester) async {
    final session = signedIn(zone: false);
    addTearDown(session.dispose);
    Uri? searchUri;
    await tester.pumpWidget(SiagaApp(session: session, baseUrl: base, autoStartNotifications: false,
      client: MockClient((request) async {
        if (request.url.path.endsWith('/locations/search')) {
          searchUri = request.url;
          expect(request.headers['Authorization'], 'Bearer memory-token');
          return http.Response(jsonEncode({'items': [suggestion]}), 200);
        }
        return request.url.path.endsWith('/health') ? ok({'status': 'ok'}) : ok(null);
      })));
    await tester.pumpAndSettle();
    final field = find.byKey(const Key('zone-search-query'));
    await tester.ensureVisible(field);
    await tester.enterText(field, ' Surabaya ');
    await tapVisible(tester, find.byKey(const Key('zone-search-btn')));
    expect(searchUri?.queryParameters, {'q': 'Surabaya', 'limit': '6'});
    await tapVisible(tester, find.widgetWithText(ListTile, 'Surabaya'));
    final vm = tester.element(field).read<ZoneViewModel>();
    expect([vm.latitude, vm.longitude, vm.selectedLocationLabel], [-7.25, 112.75, 'Surabaya']);
    expect(find.textContaining('Lintang: -7.25'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    session.clear();
  });

  testWidgets('picker centers the map and keeps the suggestion local until confirmed', (tester) async {
    final session = signedIn(zone: false);
    addTearDown(session.dispose);
    await tester.pumpWidget(SiagaApp(session: session, baseUrl: base,
      initialLocation: '/map?mode=pick_zone', tileProvider: TestTileProvider(),
      autoStartNotifications: false, client: MockClient((r) async {
        if (r.url.path.endsWith('/locations/search')) {
          return http.Response(jsonEncode({'items': [suggestion]}), 200);
        }
        return r.url.path.endsWith('/health') ? ok({'status': 'ok'}) : ok(null);
      })));
    await tester.pumpAndSettle();
    final field = find.byKey(const Key('zone-search-query'));
    await tester.ensureVisible(field);
    await tester.enterText(field, 'Surabaya');
    await tapVisible(tester, find.byKey(const Key('zone-search-btn')));
    await tapVisible(tester, find.widgetWithText(ListTile, 'Surabaya'));
    final vm = tester.element(field).read<ZoneViewModel>();
    expect(vm.latitude, isNull);
    final camera = tester.widget<FlutterMap>(find.byType(FlutterMap)).mapController!.camera;
    expect(camera.zoom, 11);
    expect(camera.center.latitude, closeTo(-7.25, 0.001));
    expect(camera.center.longitude, closeTo(112.75, 0.001));
    expect(tester.widget<TextField>(find.byKey(const Key('zone-longitude'))).controller!.text, '112.75');
    await tapVisible(tester, find.byKey(const Key('confirm-point')));
    expect([vm.latitude, vm.longitude], [-7.25, 112.75]);
    await tester.pumpWidget(const SizedBox.shrink());
    session.clear();
  });

  testWidgets('earthquake pin displays parsed measurements and tsunami potential', (tester) async {
    final item = {...marker(quakeId), 'magnitude': 5.7, 'depth_km': 10,
      'potential': 'Tidak berpotensi tsunami'};
    final dto = MapMarkerDto.fromJson(item);
    expect([dto.magnitude, dto.depthKm, dto.potential], [5.7, 10.0, item['potential']]);
    await openBrowse(tester, {...markers([quakeId]), 'items': [item]});
    await tapVisible(tester, find.byKey(const ValueKey('pin-$quakeId')));
    expect(find.text('M 5.7'), findsOneWidget);
    expect(find.text('10.0 km'), findsOneWidget);
    expect(find.text('Tidak berpotensi tsunami'), findsOneWidget);
    await closeApp(tester);
  });

  test('auth accepts lifetimes from one hour through seven days', () {
    expect(AuthData.fromJson({...authJson(), 'expires_in': 604800}).expiresIn, 604800);
    for (final value in [3599, 604801, 3600.0]) {
      expect(() => AuthData.fromJson({...authJson(), 'expires_in': value}), throwsFormatException);
    }
  });

  for (final remember in [true, false]) {
    testWidgets('Tetap masuk persists a verified token only when checked ($remember)', (tester) async {
      final store = MemorySessionStore();
      await tester.pumpWidget(SiagaApp(baseUrl: base, sessionStore: store,
        autoStartNotifications: false, client: MockClient((r) async => switch (r.url.path) {
          '/api/v1/auth/login' => ok(authJson()),
          '/api/v1/me' => ok(userJson),
          '/api/v1/health' => ok({'status': 'ok'}),
          _ => ok(null),
        })));
      await tester.pumpAndSettle();
      final checkbox = find.byKey(const Key('remember-me'));
      expect(tester.widget<CheckboxListTile>(checkbox).value, true);
      if (!remember) await tapVisible(tester, checkbox);
      await tester.enterText(find.byKey(const Key('email')), 'warga@example.test');
      await tester.enterText(find.byKey(const Key('password')), 'password long');
      await tapVisible(tester, find.byKey(const Key('submit')));
      expect(find.byKey(const Key('save-zone')), findsOneWidget);
      expect((await store.readSession())?.accessToken, remember ? 'memory-token' : null);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  test('restore verifies stored token, loads the zone, and clear removes it', () async {
    final auth = AuthData.fromJson(authJson(hasZone: true));
    final store = MemorySessionStore(initialSession: StoredSession(auth.accessToken, auth.expiresAt));
    final session = SessionCoordinator(store: store);
    addTearDown(session.dispose);
    var loaded = false;
    await session.restore(fetchMe: () async {
      expect(session.token, auth.accessToken);
      expect(session.restoring, true);
      expect(session.canNavigate, false);
      return auth.user;
    }, loadZone: () async { loaded = true; });
    expect(session.canNavigate && loaded, true);
    expect(session.restoring, false);
    session.clear();
    expect(await store.readSession(), isNull);
  });

  test('failed or expired restoration returns to login and removes the token', () async {
    final now = DateTime.utc(2026, 11, 26);
    for (final expired in [true, false]) {
      final expiry = expired ? now : now.add(const Duration(hours: 1));
      final store = MemorySessionStore(initialSession: StoredSession('old', expiry));
      final session = SessionCoordinator(now: () => now, store: store);
      addTearDown(session.dispose);
      var calls = 0;
      await session.restore(fetchMe: () async {
        calls++;
        throw http.ClientException('offline');
      });
      expect(calls, expired ? 0 : 1);
      expect(session.token, isNull);
      expect(session.restoring, false);
      expect(await store.readSession(), isNull);
    }
  });

  test('a late restore cannot replace a new login', () async {
    final auth = AuthData.fromJson(authJson(hasZone: true));
    final store = MemorySessionStore(initialSession: StoredSession('old', auth.expiresAt));
    final session = SessionCoordinator(store: store);
    addTearDown(session.dispose);
    final started = Completer<void>();
    final response = Completer<UserDto>();
    final restoring = session.restore(fetchMe: () {
      started.complete();
      return response.future;
    });
    await started.future;
    session.clear();
    session.establish(auth);
    session.confirm(auth.user, session.generation);
    response.completeError(http.ClientException('old session'));
    await restoring;
    expect(session.token, auth.accessToken);
    expect((await store.readSession())?.accessToken, auth.accessToken);
  });

  for (final allow in [true, false]) {
    testWidgets('onboarding records the choice and requests permissions only on consent ($allow)',
        (tester) async {
      final auth = AuthData.fromJson(authJson(hasZone: true));
      final store = MemorySessionStore(onboardingPrompted: false,
        initialSession: StoredSession(auth.accessToken, auth.expiresAt));
      final local = FakeLocal();
      final location = _LocationPermissions();
      SiagaApp app() => SiagaApp(baseUrl: base, sessionStore: store, autoStartNotifications: false,
        localNotificationService: local, locationService: location,
        client: MockClient((r) async => switch (r.url.path) {
          '/api/v1/me' => ok(auth.user.toJson()),
          '/api/v1/me/zone' => ok(zoneJson),
          '/api/v1/events' => emptyFeed(),
          '/api/v1/health' => ok({'status': 'ok'}),
          _ => ok(null),
        }));
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(find.byType(PermissionOnboardingDialog), findsOneWidget);
      await tapVisible(tester, find.text(allow ? 'Izinkan' : 'Nanti saja'));
      expect(await store.hasPromptedOnboarding(), true);
      expect([local.requests, location.requests], allow ? [1, 1] : [0, 0]);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byType(PermissionOnboardingDialog), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('home refresh updates optional weather and tolerates null and offline', (tester) async {
    final session = signedIn();
    addTearDown(session.dispose);
    Object? payload = weatherJson;
    bool offline = false;
    await tester.pumpWidget(SiagaApp(baseUrl: base, session: session, autoStartNotifications: false,
      client: MockClient((r) async {
        if (r.url.path.endsWith('/me/weather')) {
          if (offline) throw http.ClientException('offline');
          return ok(payload);
        }
        if (r.url.path.endsWith('/events')) return emptyFeed();
        if (r.url.path.endsWith('/health')) return ok({'status': 'ok'});
        return ok(zoneJson);
      })));
    await tester.pumpAndSettle();
    final vm = tester.element(find.byType(HomeScreen)).read<WeatherViewModel>();
    expect(vm.weather?.windSpeedKmh, 9.4);
    final temp = find.text('28°C');
    final cond = find.text('Berawan');
    expect(temp, findsOneWidget);
    expect(cond, findsOneWidget);
    final refresh = tester.widget<RefreshIndicator>(find.byType(RefreshIndicator)).onRefresh;
    payload = null;
    await refresh();
    await tester.pumpAndSettle();
    expect(vm.weather, isNull);
    expect(temp, findsNothing);
    expect(cond, findsNothing);
    offline = true;
    await refresh();
    await tester.pumpAndSettle();
    expect(vm.weather, isNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    session.clear();
  });

  testWidgets('U3: password helper only shows on Daftar when password field has focus at 360px / 200%', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(SiagaApp(
      baseUrl: base,
      autoStartNotifications: false,
      localNotificationService: const NoopLocalNotificationService(),
      textScaler: const TextScaler.linear(2),
      client: MockClient((_) async => ok({'status': 'ok'})),
    ));
    await tester.pumpAndSettle();
    expect(find.text('10–128 karakter. Spasi ikut dihitung.'), findsNothing);
    await tapVisible(tester, find.text('Daftar'));
    expect(find.text('10–128 karakter. Spasi ikut dihitung.'), findsNothing);
    await tapVisible(tester, find.byKey(const Key('password')));
    expect(find.text('10–128 karakter. Spasi ikut dihitung.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('U4: duplicate email 409 offers Pindah ke Masuk and preserves typed email at 360px / 200%', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(SiagaApp(
      baseUrl: base,
      autoStartNotifications: false,
      localNotificationService: const NoopLocalNotificationService(),
      textScaler: const TextScaler.linear(2),
      client: MockClient((r) async {
        if (r.url.path.endsWith('/health')) return ok({'status': 'ok'});
        return http.Response(
          jsonEncode({
            'code': 'EMAIL_ALREADY_REGISTERED',
            'message': 'Email sudah terdaftar. Silakan masuk.',
            'request_id': 'req-duplicate',
          }),
          409,
          headers: {'content-type': 'application/json'},
        );
      }),
    ));
    await tester.pumpAndSettle();
    await tapVisible(tester, find.text('Daftar'));
    await tester.enterText(find.byKey(const Key('name')), 'Warga');
    await tester.enterText(find.byKey(const Key('email')), 'terdaftar@siaga.test');
    await tester.enterText(find.byKey(const Key('password')), 'password panjang');
    await tapVisible(tester, find.byKey(const Key('submit')));
    await tapVisible(tester, find.byKey(const Key('switch-to-login')));
    expect(find.byKey(const Key('name')), findsNothing);
    expect(
      tester.widget<TextFormField>(find.byKey(const Key('email'))).controller!.text,
      'terdaftar@siaga.test',
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('U5: Lupa kata sandi opens honest help dialog at 360px / 200%', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(SiagaApp(
      baseUrl: base,
      autoStartNotifications: false,
      localNotificationService: const NoopLocalNotificationService(),
      textScaler: const TextScaler.linear(2),
      client: MockClient((_) async => ok({'status': 'ok'})),
    ));
    await tester.pumpAndSettle();
    await tapVisible(tester, find.byKey(const Key('forgot-password')));
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.textContaining('belum tersedia di versi ini'), findsOneWidget);
    await tapVisible(tester, find.text('Mengerti'));
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('UI-05: unread 0 on Profile uses neutral StatusPill without Badge at 360px / 200%', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final session = signedIn();
    addTearDown(session.dispose);
    await tester.pumpWidget(SiagaApp(
      baseUrl: base,
      session: session,
      initialLocation: '/profile',
      autoStartNotifications: false,
      localNotificationService: const NoopLocalNotificationService(),
      textScaler: const TextScaler.linear(2),
      client: MockClient((r) async => switch (r.url.path) {
        '/api/v1/health' => ok({'status': 'ok'}),
        '/api/v1/me/zone' => ok(zoneJson),
        '/api/v1/notifications' => ok({
          'items': <Object>[],
          'page': {'limit': 20, 'offset': 0, 'next_offset': null, 'has_more': false},
          'unread_count': 0,
        }),
        _ => ok(null),
      }),
    ));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(ProfileScreen),
        matching: find.byType(Badge),
      ),
      findsNothing,
    );
    expect(find.text('0'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    session.clear();
  });

  testWidgets('TsunamiPotentialBox renders error tone for Berpotensi tsunami at 360px / 200%', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: appTheme(),
      home: MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: const Scaffold(
          body: Padding(
            padding: EdgeInsets.all(16),
            child: TsunamiPotentialBox(potential: 'Berpotensi tsunami'),
          ),
        ),
      ),
    ));
    expect(find.byIcon(Icons.tsunami), findsOneWidget);
    final title = tester.widget<Text>(find.text('Potensi'));
    expect(title.style?.color, AppColors.error);
    expect(tester.takeException(), isNull);
  });
}
