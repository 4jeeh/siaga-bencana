// Explicit opt-in test; scripts/smoke_live.py supplies an isolated local API.
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:siaga_bencana/core/network/api_client.dart';
import 'package:siaga_bencana/core/network/api_envelope.dart';
import 'package:siaga_bencana/core/session/session_coordinator.dart';
import 'package:siaga_bencana/features/auth/auth_dto.dart';
import 'package:siaga_bencana/features/auth/auth_repository.dart';
import 'package:siaga_bencana/features/events/event_repository.dart';
import 'package:siaga_bencana/features/map/map_repository.dart';
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
    session.establish(loggedIn);
    session.confirm(await repository.me(), session.generation);
    final events = EventRepository(api);
    final feed = await events.fetchEvents(radiusOnly: true);
    expect(feed.meta.zoneVersion, 2);
    expect(feed.meta.sources.map((source) => source.source),
        unorderedEquals(['BMKG_TEWS', 'BMKG_NOWCAST']));
    expect(feed.page.limit, 20);
    expect(
      feed.items.map((item) => item.id),
      containsAll([
        '30000000-0000-4000-8000-000000000001',
        '30000000-0000-4000-8000-000000000002',
      ]),
    );
    final quakeDetail = await events.fetchEventDetail('30000000-0000-4000-8000-000000000001');
    expect(quakeDetail.meta.zoneVersion, 2);
    expect(quakeDetail.data.earthquake?.potential, 'Tidak berpotensi tsunami');
    expect(quakeDetail.data.priority.withinRadius, isTrue);
    final capDetail = await events.fetchEventDetail('30000000-0000-4000-8000-000000000002');
    expect(capDetail.meta.zoneVersion, 2);
    expect(capDetail.data.priority.matchMethod, 'inside_polygon');
    expect(capDetail.data.areas.single.polygons.single.crossesAntimeridian, isTrue);
    expect(
      capDetail.data.references.single.referencedEventId,
      '30000000-0000-4000-8000-000000000003',
    );
    await expectLater(
      events.fetchEventDetail('30000000-0000-4000-8000-000000000999'),
      throwsA(
        isA<ApiErrorEnvelope>()
            .having((e) => e.statusCode, 'statusCode', 404)
            .having((e) => e.code, 'code', 'RESOURCE_NOT_FOUND'),
      ),
    );
    final markers = await MapRepository(api).fetchMarkers(
      bbox: '179,-9,-179,-5', radiusOnly: true, includeReports: true,
    );
    expect(markers.meta.zoneVersion, 2);
    expect(markers.cap, 100);
    expect(markers.truncated, isFalse);
    expect(markers.items, isNotEmpty);
  });
}
