// Explicit opt-in test; scripts/smoke_live.py supplies an isolated local API.
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:siaga_bencana/core/network/api_client.dart';
import 'package:siaga_bencana/core/session/session_coordinator.dart';
import 'package:siaga_bencana/features/auth/auth_dto.dart';
import 'package:siaga_bencana/features/auth/auth_repository.dart';
import 'package:siaga_bencana/features/zone/zone_dto.dart';
import 'package:siaga_bencana/features/zone/zone_repository.dart';

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
    expect((await api.get('/ready')).requiredData['status'], 'ready');
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
    final zones = ZoneRepository(api);
    expect(await zones.fetchZone(), isNull);
    const request = ZoneUpdateRequest(latitude: -7.25, longitude: 112.75);
    final created = await zones.saveZone(request);
    expect(created.zoneVersion, 1);
    expect((await repository.me()).hasZone, true);
    expect(session.markZoneSaved(session.generation), true);
    expect(session.user!.hasZone, true);
    final identical = await zones.saveZone(request);
    expect(identical.zoneVersion, 1);
    expect(identical.alertEligibleSince, created.alertEligibleSince);
    expect(identical.updatedAt, created.updatedAt);
    // Send raw +180 deliberately: verify server canonicalization, not only DTO normalization.
    final changed = ZoneDto.fromJson((await api.put('/me/zone', {
      ...request.toJson(), 'longitude': 180,
    })).requiredData);
    expect(changed.zoneVersion, 2);
    expect(changed.longitude, -180.0);
    expect((await zones.fetchZone())!.zoneVersion, 2);
    session.clear();
    final loggedIn = await repository.login(
      const LoginRequest('smoke@example.test', password),
    );
    expect(loggedIn.user.id, auth.user.id);
    expect(loggedIn.expiresAt.isAfter(DateTime.now().toUtc()), true);
  });
}
