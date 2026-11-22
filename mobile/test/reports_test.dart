import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:provider/provider.dart';
import 'package:siaga_bencana/app.dart';
import 'package:siaga_bencana/core/network/api_client.dart';
import 'package:siaga_bencana/core/network/api_envelope.dart';
import 'package:siaga_bencana/core/session/session_coordinator.dart';
import 'package:siaga_bencana/features/auth/auth_dto.dart';
import 'package:siaga_bencana/features/events/event_repository.dart';
import 'package:siaga_bencana/features/reports/moderation_view_model.dart';
import 'package:siaga_bencana/features/reports/report_dto.dart';
import 'package:siaga_bencana/features/reports/report_form.dart';
import 'package:siaga_bencana/features/reports/report_panel.dart';
import 'package:siaga_bencana/features/reports/report_photo_service.dart';
import 'package:siaga_bencana/features/reports/report_repository.dart';
import 'package:siaga_bencana/features/reports/report_text.dart';
import 'package:siaga_bencana/features/reports/reports_view_model.dart';
import 'package:siaga_bencana/features/zone/zone_repository.dart';
import 'package:siaga_bencana/features/zone/zone_view_model.dart';

import 'event_detail_fixtures.dart' show quakeDetail, quakeKey;
import 'map_browse_test.dart' as map_fixture show markers, reportId;
import 'events_feed_test.dart' show Json, at, failure, feed, response;
import 'widget_test.dart' show FakeLocationService, TestTileProvider, base, emptyFeed, meta, ok, signedIn, userJson, zoneJson;

const reportId = '41000000-0000-4000-8000-000000000001';
const description = 'Air sudah mencapai jalan di dekat jembatan.';
Json report({String id = reportId, String status = 'verified', bool private = false,
    bool photo = false, String owner = 'citizen', String? reviewer, int version = 1}) => {
  'id': id, 'source': 'CITIZEN', 'event_id': null, 'category': 'flood', 'description': description,
  'latitude': -7.25, 'longitude': 112.75, 'created_at': at, 'verified_at': status == 'verified' ? at : null,
  'status': status, 'is_simulated': false, 'has_photo': photo, 'match_distance_km': 1.25,
  if (private) ...{'reporter_id': owner, 'reviewer_id': reviewer, 'version': version, 'latest_reason': 'Catatan admin'},
};
class FakeReportPhotoService implements ReportPhotoService {
  bool denied = false, cancel = false;
  final photo = compressReportPhotoBytes(img.encodePng(img.Image(width: 12, height: 8)));
  @override
  Future<ProcessedReportPhoto?> pickAndCompress(ReportPhotoSource source) async {
    if (denied) throw const PhotoProcessingFailure('Izin foto ditolak.');
    return cancel ? null : photo;
  }
}
SessionCoordinator account(bool admin) {
  final session = signedIn();
  if (admin) session.confirm(UserDto.fromJson({...userJson, 'role': 'admin', 'has_zone': true}), session.generation);
  return session;
}
class Harness {
  Harness(Future<http.Response> Function(http.Request) handle, {bool admin = false}) : session = account(admin) {
    api = ApiClient(client: MockClient(handle), baseUrl: base, session: session);
    zone = ZoneViewModel(ZoneRepository(api), session, location);
    repository = ReportRepository(api);
    vm = ReportsViewModel(repository, EventRepository(api), session, zone, location, photos);
    mod = ModerationViewModel(repository, session, zone)..refreshReports = vm.refreshLists;
    addTearDown(() { mod.dispose(); vm.dispose(); zone.dispose(); api.close(); session.dispose(); });
  }
  final SessionCoordinator session;
  final photos = FakeReportPhotoService();
  final location = FakeLocationService();
  late final ApiClient api;
  late final ZoneViewModel zone;
  late final ReportRepository repository;
  late final ReportsViewModel vm;
  late final ModerationViewModel mod;
  Future<void> prepare() async { vm.setCategory('flood'); vm.setDescription(description); await vm.gps(); }
}

Future<void> scrollTo(WidgetTester tester, Finder target, Finder container, {double delta = 200}) async {
  await tester.pumpAndSettle();
  final scroll = find.descendant(of: container, matching: find.byType(Scrollable)).first;
  if (target.evaluate().isEmpty) {
    await tester.scrollUntilVisible(target, delta, scrollable: scroll);
  }
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
}
Future<void> openApp(WidgetTester tester, SessionCoordinator session, Future<http.Response> Function(http.Request) handle,
    {String route = '/reports', FakeReportPhotoService? photos}) async {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset); addTearDown(session.dispose);
  await tester.pumpWidget(SiagaApp(session: session, baseUrl: base, initialLocation: route, textScaler: const TextScaler.linear(2),
    locationService: FakeLocationService(), photoService: photos ?? FakeReportPhotoService(), tileProvider: TestTileProvider(), client: MockClient((request) async {
      if (request.url.path.endsWith('/health')) return ok({'status': 'ok'});
      if (request.url.path.endsWith('/events')) return emptyFeed();
      if (request.url.path.endsWith('/me/zone')) return ok(zoneJson);
      return handle(request);
    })));
  await tester.pumpAndSettle();
}

Future<void> closeApp(WidgetTester tester) async {
  final session = tester.element(find.byType(Scaffold).first).read<SessionCoordinator>();
  await tester.pumpWidget(const SizedBox.shrink());
  session.clear();
}

void main() {
  test('compression rejects undecodable data, does not upscale, bounds portrait and landscape, strips EXIF', () {
    expect(() => compressReportPhotoBytes(Uint8List(2)), throwsA(isA<PhotoProcessingFailure>()));
    for (final size in [(40, 20, 40, 20), (1200, 600, 1024, 512), (600, 1200, 512, 1024)]) {
      final photo = compressReportPhotoBytes(img.encodePng(img.Image(width: size.$1, height: size.$2)));
      expect((photo.width, photo.height), (size.$3, size.$4));
      expect(photo.byteLength, photo.bytes.length); expect(photo.byteLength, lessThanOrEqualTo(2097152));
      final decoded = img.decodeJpg(photo.bytes)!;
      expect((decoded.width, decoded.height), (size.$3, size.$4)); expect(decoded.exif.isEmpty, isTrue);
    }
  });
  test('NFC and UUIDv4 use canonical text and independent request IDs', () {
    expect(normalizeReportText('  cafe\u0301 '), 'café'); expect(normalizeReportText('\u1100\u1161'), '가');
    final keys = List.generate(30, (_) => generateUuidV4());
    expect(keys.toSet(), hasLength(30)); expect(keys, everyElement(matches(RegExp(r'^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$'))));
  });
  test('uncertain upload replays same fields and JPEG; edit rotates UUID; conflict blocks unchanged data', () async {
    final uploads = <http.Request>[];
    final harness = Harness((request) async {
      uploads.add(request);
      return uploads.length == 3 ? failure('IDEMPOTENCY_CONFLICT', 409) : failure('UNAVAILABLE', 503);
    });
    final vm = harness.vm; await harness.prepare(); await vm.pickPhoto(ReportPhotoSource.gallery);
    await vm.submit(); final key = vm.lockedKey!;
    expect(vm.submitError, contains('Cek tab Saya'));
    await vm.submit(); expect(vm.lockedKey, key);
    String payload(http.Request request) {
      final boundary = request.headers['content-type']!.split('boundary=').last;
      return latin1.decode(request.bodyBytes).replaceAll(boundary, 'BOUNDARY');
    }
    final first = payload(uploads.first);
    expect(first, payload(uploads[1])); expect(first, contains(key)); expect(first, contains(latin1.decode(harness.photos.photo.bytes)));
    expect(first, contains('name="photo"; filename="report.jpg"')); expect(first, contains('image/jpeg'));
    for (final forbidden in ['event_id', 'payload_hash', 'reporter_id', 'status', 'version', 'reviewer_id', 'is_simulated']) {
      expect(first, isNot(contains('name="$forbidden"')));
    }
    expect(uploads.first.headers['Authorization'], 'Bearer memory-token');
    vm.setEvent('related'); expect(vm.lockedKey, isNull); expect(vm.contentChangedNotice, 'Isi berubah, akan menjadi laporan baru');
    expect(uploads, hasLength(2)); await vm.submit(); expect(payload(uploads.last), isNot(contains(key)));
    expect(payload(uploads.last), contains('name="event_id"')); expect(vm.canSubmit, isFalse); await vm.submit(); expect(uploads, hasLength(3));
  });
  test('failed photo replacement blocks upload until explicit removal or successful retry', () async {
    final harness = Harness((_) async => emptyFeed()); final vm = harness.vm;
    await harness.prepare(); await vm.pickPhoto(ReportPhotoSource.gallery); final before = vm.draftPhoto;
    harness.photos.denied = true; await vm.pickPhoto(ReportPhotoSource.camera);
    expect(vm.draftPhoto, same(before)); expect(vm.photoError, isNotNull); expect(vm.canSubmit, isFalse);
    harness.photos.denied = false; harness.photos.cancel = true; await vm.pickPhoto(ReportPhotoSource.gallery);
    expect(vm.canSubmit, isFalse); vm.removePhoto(); expect(vm.draftPhoto, isNull); expect(vm.canSubmit, isTrue);
  });
  test('late responses cannot restore private feed or draft after logout', () async {
    final pending = Completer<http.Response>(); final harness = Harness((_) => pending.future); await harness.prepare();
    final load = harness.vm.loadMine(); harness.session.clear(); pending.complete(response(feed([report(private: true)]))); await load;
    expect(harness.vm.mine.items, isEmpty); expect(harness.vm.draftDescription, isEmpty); expect(harness.vm.draftLatitude, isNull);
    expect(harness.vm.lockedKey, isNull); expect(harness.vm.mine.error, isNull);
  });
  test('independent lists, filter reset and ordered deduplication across pages', () async {
    final queries = <Map<String,String>>[];
    final harness = Harness((request) async {
      final query = request.url.queryParameters; queries.add(query);
      if (query['scope'] == 'mine') return response(feed([report(private: true)]));
      return response(query['offset'] == '0' ? feed([report()], next: 20) : feed([report(), report(id: 'second')], offset: 20));
    });
    final vm = harness.vm; await vm.loadMine(); await vm.loadNearby(); await vm.loadNearby(more: true);
    expect(vm.nearby.items.map((item) => item.id), [reportId, 'second']); expect(vm.mine.items.single.isPrivate, isTrue);
    vm.filterNearby('flood'); await Future<void>.delayed(Duration.zero);
    expect(queries.last, containsPair('category','flood')); expect(queries.last['offset'], '0'); expect(vm.mine.page, isNotNull);
  });
  test('multipart maps replay, malformed responses, stale session and 401', () async {
    var mode = 0;
    final started = Completer<void>();
    final pending = Completer<http.Response>();
    final harness = Harness((_) async {
      if (mode == 4) started.complete();
      return switch (mode) {
      0 => http.Response(jsonEncode({'data': report(private: true), 'meta': meta}), 200, headers: {'Idempotent-Replay': 'true'}),
      1 => http.Response('not json', 200), 2 => throw http.ClientException('offline'), 3 => failure('AUTH_REQUIRED', 401), _ => await pending.future,
      };
    });
    Future<MultipartApiEnvelope> send() => harness.api.postMultipart('/reports', fields: {});
    expect((await send()).idempotentReplay, isTrue);
    for (final entry in [(1,'INVALID_RESPONSE'), (2,'NETWORK_ERROR')]) {
      mode = entry.$1; await expectLater(send(), throwsA(isA<ApiErrorEnvelope>().having((error) => error.code, 'code', entry.$2)));
    }
    for (final invalid in ['../abc','a/b','a?b','a#b','']) { await expectLater(harness.repository.fetchReportDetail(invalid), throwsArgumentError); }
    mode = 4; final old = send(); await started.future; mode = 3; await expectLater(send(), throwsA(isA<ApiErrorEnvelope>()));
    expect(harness.session.isValid, isFalse); pending.complete(ok(report()));
    await expectLater(old, throwsA(isA<ApiErrorEnvelope>().having((error) => error.code,'code','SESSION_CHANGED')));
  });
  for (final scenario in ['success', 'conflict', 'timeout']) {
    test('moderation $scenario reconciles detail, audit, and all three feeds without action replay', () async {
      var status = 'pending', version = 1;
      final moderator = userJson['id'] as String;
      String? reviewer;
      final posts = <String>[], bodies = <Json>[], reads = <String>[];
      final harness = Harness((request) async {
        final suffix = request.url.pathSegments.last;
        if (request.method == 'POST') {
          posts.add(suffix); bodies.add(jsonDecode(request.body) as Json);
          version++;
          if (suffix == 'claim') { status = 'in_review'; reviewer = moderator; }
          else {
            status = scenario == 'success' ? 'verified' : 'rejected';
            if (scenario == 'conflict') return failure('VERSION_CONFLICT', 409);
            if (scenario == 'timeout') throw http.ClientException('timeout');
          }
          return ok({'id': reportId, 'status': status, 'reviewer_id': reviewer, 'version': version, 'claimed_at': at, 'decided_at': null});
        }
        reads.add(request.url.queryParameters['scope'] ?? suffix);
        return suffix == reportId ? ok(report(private: true, status: status, reviewer: reviewer, version: version)) : emptyFeed();
      }, admin: true);
      final mod = harness.mod;
      await mod.openId(reportId); await mod.claimActiveReport(); expect(mod.canDecide, isTrue);
      expect(bodies.single, {'expected_version': 1}); mod.setReason(' too short '); await mod.submitDecision('verified'); expect(posts, ['claim']);
      mod.setReason('  Data sesuai kondisi lapangan.  '); mod.decisionDialogOpen = true; reads.clear();
      await mod.submitDecision('verified'); expect(posts, ['claim', 'decision']);
      expect(bodies.last, {'expected_version': 2, 'outcome': 'verified', 'reason': 'Data sesuai kondisi lapangan.'});
      expect(reads, unorderedEquals([reportId, 'verifications', 'nearby', 'mine', 'review']));
      expect(mod.decisionDialogOpen, isFalse); expect(mod.panelReport!.status, status); expect(mod.panelReport!.version, 3);
      expect(mod.draftReason.trim(), scenario == 'success' ? '' : 'Data sesuai kondisi lapangan.');
      if (scenario == 'conflict') { expect(mod.conflictMessage, contains('versi 3')); expect(mod.conflictMessage, contains(moderator)); }
      if (scenario == 'timeout') expect(mod.actionError, isNotNull);
    });
  }
  test('public panel requests signed photo only on open; exactly one refresh then fallback', () async {
    final paths = <String>[];
    final harness = Harness((request) async {
      final path = request.url.pathSegments.last; paths.add(path);
      if (path == 'reports') return response(feed([report(photo: true)]));
      if (path == 'photo-url') return ok({'url': 'https://photos.example.test/signed', 'expires_at': at, 'expires_in': 300, 'content_type': 'image/jpeg', 'is_simulated': false});
      return ok(report(photo: true));
    });
    await harness.vm.loadNearby(); expect(paths, ['reports']); final mod = harness.mod;
    await mod.openPanel(harness.vm.nearby.items.single); expect(paths, ['reports', reportId, 'photo-url']);
    final revision = mod.photoRevision; await mod.refreshPhotoUrlOnce(revision: revision); await mod.refreshPhotoUrlOnce(revision: revision);
    expect(mod.photoUrl, isNotNull); await mod.refreshPhotoUrlOnce(); expect(mod.photoError, 'Foto tidak dapat dimuat.');
    expect(paths.where((path) => path == 'photo-url'), hasLength(2)); expect(paths, isNot(contains('verifications')));
    mod.closePanel(); expect(mod.photoUrl, isNull); expect(mod.panelReport, isNull);
  });
  testWidgets('citizen composes with manual point, prefilled event, photo recovery and keyboard at 200%', (tester) async {
    final photos = FakeReportPhotoService(); final uploads = <http.Request>[];
    await openApp(tester, account(false), (request) async {
      if (request.method == 'POST') { uploads.add(request); return ok(report(private: true, status: 'pending'), status: 201); }
      return emptyFeed();
    }, route: '/reports?event_id=related-event', photos: photos);
    expect(find.text('Terkait event: related-event'), findsOneWidget); expect(find.text('Tinjau'), findsNothing);
    await tester.tap(find.text('Tulis Laporan')); await tester.pumpAndSettle(); final form = find.byType(ReportForm);
    final vm = tester.element(form).read<ReportsViewModel>();
    await tester.tap(find.byType(DropdownButtonFormField<String>)); await tester.pumpAndSettle();
    await tester.tap(find.text('Banjir').last); await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), description);
    await tester.pumpAndSettle();
    await scrollTo(tester, find.text('Pilih titik manual'), form); await tester.tap(find.text('Pilih titik manual')); await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsNothing);
    await tester.enterText(find.byKey(const Key('zone-latitude')), '-7.125');
    await tester.enterText(find.byKey(const Key('zone-longitude')), '180');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('confirm-point')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-point')));
    await tester.pumpAndSettle();
    expect(vm.draftLongitude, -180); expect(vm.zone.savedZone!.longitude, 112.75); expect(form, findsOneWidget);
    await scrollTo(tester, find.text('Pilih galeri'), form); await tester.tap(find.text('Pilih galeri')); await tester.pumpAndSettle();
    expect(vm.draftPhoto, isNotNull); photos.denied = true;
    await scrollTo(tester, find.text('Pilih galeri'), form); await tester.tap(find.text('Pilih galeri')); await tester.pumpAndSettle(); expect(vm.canSubmit, isFalse);
    await scrollTo(tester, find.text('Hapus foto'), form); expect(find.text('Pilih Ulang'), findsOneWidget);
    await tester.tap(find.text('Hapus foto')); await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 250); await tester.pumpAndSettle();
    await scrollTo(tester, find.text('Kirim'), form); await tester.tap(find.text('Kirim')); await tester.pumpAndSettle();
    expect(uploads, hasLength(1)); expect(form, findsNothing); expect(tester.takeException(), isNull);
    await closeApp(tester);
  });
  testWidgets('reviewer conflict closes dialog, preserves reason and announces refreshed version at 200%', (tester) async {
    final session = account(true); var version = 4; final submitted = <Json>[];
    Json current() => report(private: true, status: version == 4 ? 'in_review' : 'rejected', reviewer: session.user!.id, version: version);
    await openApp(tester, session, (request) async {
      if (request.url.path.endsWith('/decision')) { submitted.add(jsonDecode(request.body) as Json); version++; return failure('VERSION_CONFLICT', 409); }
      if (request.url.path.endsWith(reportId)) return ok(current());
      if (request.url.queryParameters['scope'] == 'review') return response(feed([current()]));
      return emptyFeed();
    });
    await tester.ensureVisible(find.text('Tinjau')); await tester.tap(find.text('Tinjau')); await tester.pumpAndSettle();
    await scrollTo(tester, find.text('Lihat / Tinjau'), find.byType(RefreshIndicator));
    await tester.tap(find.text('Lihat / Tinjau')); await tester.pumpAndSettle();
    await scrollTo(tester, find.text('Tolak'), find.byType(ReportPanel)); await tester.tap(find.text('Tolak')); await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Simpan keputusan')).onPressed, isNull);
    await tester.enterText(find.byType(TextFormField), '  Bukti lokasi belum sesuai.  '); await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Simpan keputusan')); await tester.tap(find.text('Simpan keputusan')); await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing); expect(submitted.single, {'outcome': 'rejected', 'expected_version': 4, 'reason': 'Bukti lokasi belum sesuai.'});
    final mod = tester.element(find.byType(ReportPanel)).read<ModerationViewModel>();
    expect(mod.draftReason.trim(), 'Bukti lokasi belum sesuai.'); expect(find.text(mod.conflictMessage!), findsOneWidget);
    expect(find.text('Setujui'), findsNothing); expect(tester.takeException(), isNull);
    await closeApp(tester);
  });
  testWidgets('map marker loads detail only on explicit full-report action', (tester) async {
    final paths = <String>[];
    await openApp(tester, account(false), (request) async {
      final path = request.url.path; paths.add(path);
      if (path.endsWith('/map/markers')) return response(map_fixture.markers([map_fixture.reportId]));
      return ok(report(id: map_fixture.reportId));
    }, route: '/map');
    await tester.pump(const Duration(milliseconds: 300)); await tester.pumpAndSettle();
    final pin = find.byKey(const ValueKey('pin-${map_fixture.reportId}'));
    await tester.ensureVisible(pin); await tester.tap(pin); await tester.pumpAndSettle();
    expect(paths.where((path) => path.contains('/reports/')), isEmpty);
    await tester.ensureVisible(find.text('Lihat laporan penuh')); await tester.tap(find.text('Lihat laporan penuh')); await tester.pumpAndSettle();
    expect(paths.where((path) => path.endsWith('/reports/${map_fixture.reportId}')), hasLength(1));
    expect(find.descendant(of: find.byType(ReportPanel), matching: find.text(description)), findsOneWidget);
    expect(find.text('Jejak peninjauan'), findsNothing); await closeApp(tester);
  });
  testWidgets('related reports fail independently of BMKG detail', (tester) async {
    final scopes = <Map<String,String>>[];
    await openApp(tester, account(false), (request) async {
      if (request.url.path.endsWith('/events/$quakeKey')) return response(quakeDetail());
      scopes.add(request.url.queryParameters); return failure('UNAVAILABLE', 503);
    }, route: '/events/$quakeKey');
    expect(scopes, contains(equals({'scope': 'verified', 'event_id': quakeKey, 'limit': '20', 'offset': '0'})));
    expect(find.text('Gagal memuat detail'), findsNothing);
    final list = find.byKey(const ValueKey('detail-list-$quakeKey'));
    await scrollTo(tester, find.text('Gagal memuat.'), list);
    expect(find.text('Laporan warga terkait'), findsOneWidget); await closeApp(tester);
  });
  for (final self in [true, false]) {
    testWidgets('admin cannot moderate ${self ? "own" : "another reviewer’s"} report', (tester) async {
      final session = account(true); final paths = <String>[];
      final data = report(private: true, owner: self ? session.user!.id : 'citizen', reviewer: self ? null : 'other-admin', status: self ? 'pending' : 'in_review');
      await openApp(tester, session, (request) async {
        paths.add(request.url.pathSegments.last);
        if (request.url.path.endsWith(reportId)) return ok(data);
        if (request.url.queryParameters['scope'] == 'review') return response(feed([data]));
        return emptyFeed();
      });
      await tester.ensureVisible(find.text('Tinjau')); await tester.tap(find.text('Tinjau')); await tester.pumpAndSettle();
      await scrollTo(tester, find.text('Lihat / Tinjau'), find.byType(RefreshIndicator));
      await tester.tap(find.text('Lihat / Tinjau')); await tester.pumpAndSettle();
      expect(paths, contains('verifications')); expect(find.text('Jejak peninjauan'), findsOneWidget);
      expect(find.text('Setujui'), findsNothing); expect(find.text('Tolak'), findsNothing);
      if (self) {
        expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Tidak dapat meninjau laporan sendiri')).onPressed, isNull);
      } else { expect(find.textContaining('Sedang ditinjau oleh admin lain'), findsOneWidget); }
      await closeApp(tester);
    });
  }
  test('nearby rejects stale zone version while mine remains usable', () async {
    final harness = Harness((request) async => request.url.path.endsWith('/me/zone') ? ok(zoneJson) : response(feed([report()], version: 0)));
    await harness.zone.load(); await harness.vm.loadNearby(); await harness.vm.loadMine();
    expect(harness.vm.nearby.items, isEmpty); expect(harness.vm.nearby.error, contains('zona terbaru')); expect(harness.vm.mine.items, hasLength(1));
  });
  test('network retry freezes bytes, edits invalidate the snapshot without submitting', () async {
    var calls = 0;
    final harness = Harness((request) async { calls++; throw http.ClientException('offline'); });
    await harness.prepare(); final vm = harness.vm;
    await vm.pickPhoto(ReportPhotoSource.camera);
    final keys = <String>{};
    for (final change in <void Function()>[
      () => vm.setCategory('earthquake'), () => vm.setDescription('$description Terbaru.'),
      () => vm.selectDraftPoint(0, 0), () => vm.setEvent('event'), vm.removePhoto,
    ]) {
      await vm.submit(); expect(keys.add(vm.lockedKey!), isTrue); final previous = calls;
      change(); expect(vm.lockedKey, isNull); expect(calls, previous); expect(vm.contentChangedNotice, 'Isi berubah, akan menjadi laporan baru');
    }
  });
  test('compression respects orientation and rejects images beyond the pixel limit', () {
    final rotated = img.Image(width: 80, height: 40)..exif.imageIfd.orientation = 6;
    final photo = compressReportPhotoBytes(img.encodeJpg(rotated));
    expect((photo.width, photo.height), (40, 80));
    expect(img.decodeJpg(photo.bytes)!.exif.isEmpty, isTrue);
    final large = img.encodePng(img.Image(width: 4001, height: 4000, numChannels: 1));
    expect(() => compressReportPhotoBytes(large), throwsA(isA<PhotoProcessingFailure>()));
  });
  test('event choices request the unfiltered first page; freshness stays independent', () async {
    final requests = <Uri>[];
    final harness = Harness((request) async { requests.add(request.url); return emptyFeed(); });
    await harness.vm.loadEvents(); expect(requests.single.path, '/api/v1/events');
    expect(requests.single.queryParameters, {'radius_only': 'false', 'limit': '20', 'offset': '0'});
    expect(harness.vm.eventsMeta!.sources, hasLength(2)); expect(harness.vm.nearby.meta, isNull);
  });
  testWidgets('signed images are uncredentialed and remain optional when rendering fails', (tester) async {
    var urls = 0;
    final harness = Harness((request) async {
      if (request.url.path.endsWith('/photo-url')) {
        urls++;
        return ok({'url': 'https://example.invalid/signed/$urls', 'expires_at': at, 'expires_in': 300, 'content_type': 'image/jpeg', 'is_simulated': false});
      }
      return ok(report(photo: true));
    });
    await harness.mod.openId(reportId);
    await tester.pumpWidget(ChangeNotifierProvider.value(value: harness.mod,
      child: const MaterialApp(home: Scaffold(body: ReportPanel(id: reportId)))));
    final image = tester.widget<Image>(find.byType(Image));
    expect(image.semanticLabel, 'Foto laporan warga'); expect((image.image as NetworkImage).headers, isNull);
    for (var attempt = 0; attempt < 2; attempt++) {
      final finder = find.byType(Image);
      if (finder.evaluate().isNotEmpty) {
        tester.widget<Image>(finder).errorBuilder!(tester.element(finder), StateError('offline'), null);
      }
      await tester.pump(); await tester.pumpAndSettle();
    }
    expect(urls, 2); expect(find.text('Foto tidak dapat dimuat.'), findsOneWidget); expect(find.text(description), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink()); harness.session.clear();
  });
  test('page error leaves existing items intact; ZONE_REQUIRED is isolated to nearby', () async {
    var missingZone = true, failPage = true;
    final harness = Harness((request) async {
      final query = request.url.queryParameters;
      if (query['scope'] == 'nearby' && missingZone) return failure('ZONE_REQUIRED', 409);
      if (query['offset'] == '20' && failPage) return failure('UNAVAILABLE', 503);
      return response(query['offset'] == '0' ? feed([report()], next: 20) : feed([report(id: 'next')], offset: 20));
    });
    final vm = harness.vm; await vm.loadNearby(); await vm.loadMine();
    expect(vm.nearby.zoneRequired, isTrue); expect(vm.mine.zoneRequired, isFalse);
    missingZone = false; await vm.loadNearby(); await vm.loadNearby(more: true);
    expect(vm.nearby.error, isNull); expect(vm.nearby.loadMoreError, isNotNull); expect(vm.nearby.items.single.id, reportId);
    failPage = false; await vm.loadNearby(more: true); expect(vm.nearby.loadMoreError, isNull); expect(vm.nearby.items, hasLength(2));
  });
}
