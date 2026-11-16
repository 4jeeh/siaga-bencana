// Explicit opt-in test; scripts/smoke_live.py supplies an isolated local API.
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:siaga_bencana/core/network/api_client.dart';
import 'package:siaga_bencana/core/session/session_coordinator.dart';
import 'package:siaga_bencana/features/auth/auth_dto.dart';
import 'package:siaga_bencana/features/auth/auth_repository.dart';

void main() {
  test('real Flutter HTTP -> Uvicorn -> PostgreSQL auth round trip', () async {
    const address = String.fromEnvironment('LIVE_API_URL');
    expect(address, isNotEmpty, reason: 'Run backend/scripts/smoke_live.py');
    final uri = Uri.parse(address);
    expect(uri.host, '127.0.0.1');
    final session = SessionCoordinator();
    final api = ApiClient(
      client: http.Client(),
      baseUrl: uri,
      session: session,
    );
    addTearDown(() {
      api.close();
      session.dispose();
    });
    final repository = AuthRepository(api);
    expect((await repository.health()).mode, 'local_live');
    expect((await api.get('/ready')).data['status'], 'ready');
    const password = '  Live smoke password  ';
    final auth = await repository.register(
      const RegisterRequest(' SMOKE@EXAMPLE.TEST ', password, ' Live Smoke '),
    );
    expect(auth.user.email, 'smoke@example.test');
    expect(auth.user.displayName, 'Live Smoke');
    expect(auth.user.hasZone, false);
    session.establish(auth);
    final user = await repository.me();
    session.confirm(user, session.generation);
    expect(user.id, auth.user.id);
    expect(user.role, 'citizen');
    session.clear();
    final loggedIn = await repository.login(
      const LoginRequest('smoke@example.test', password),
    );
    expect(loggedIn.user.id, auth.user.id);
    expect(loggedIn.expiresAt.isAfter(DateTime.now().toUtc()), true);
  });
}
