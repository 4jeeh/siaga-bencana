import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
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
http.Response ok(Object data, {int status = 200}) => http.Response(
  jsonEncode({'data': data, 'meta': meta}),
  status,
  headers: {'content-type': 'application/json'},
);
SessionCoordinator signedIn({bool zone = true}) {
  final session = SessionCoordinator();
  final auth = AuthData.fromJson(authJson(hasZone: zone));
  session.establish(auth);
  session.confirm(auth.user, session.generation);
  return session;
}

void main() {
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
      '${register ? 'register' : 'login'} -> me -> zone placeholder, no zone API',
      (tester) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final paths = <String>[];
        final mock = MockClient((request) async {
          paths.add(request.url.path);
          if (request.url.path.endsWith('/health')) return ok({'status': 'ok'});
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
      await tester.pumpWidget(
        SiagaApp(
          client: MockClient((_) async => ok({'status': 'ok'})),
          baseUrl: base,
          session: session,
          initialLocation: '/events/demo-id',
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
        expect(
          find.text('Dalam pengembangan Slice berikutnya'),
          findsOneWidget,
        );
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
