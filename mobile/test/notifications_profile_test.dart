import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:siaga_bencana/app.dart';
import 'package:siaga_bencana/core/network/api_client.dart';
import 'package:siaga_bencana/core/network/sse_client.dart';
import 'package:siaga_bencana/features/event_detail/event_detail_screen.dart';
import 'package:siaga_bencana/features/notifications/local_notification_service.dart';
import 'package:siaga_bencana/features/notifications/notification_coordinator.dart';
import 'package:siaga_bencana/features/notifications/notification_dto.dart';
import 'package:siaga_bencana/features/notifications/notification_repository.dart';
import 'package:siaga_bencana/features/notifications/notification_view_model.dart';
import 'package:siaga_bencana/features/profile/profile_screen.dart';

import 'event_detail_fixtures.dart';
import 'widget_test.dart' show base, emptyFeed, ok, signedIn, tapVisible,
    TestTileProvider, userJson, zoneJson;

typedef Json = Map<String, dynamic>;
const owner = '10000000-0000-4000-8000-000000000001';
const stamp = '2026-11-16T03:00:00Z';
const meta = {'mode': 'simulation', 'is_simulated': true, 'server_time': stamp};

Json record(int seq, {bool active = true}) => {
  'id': '70000000-0000-4000-8000-${seq.toString().padLeft(12, '0')}',
  'event_id': quakeKey, 'kind': 'official_new', 'sequence': seq, 'zone_version': 1,
  'priority_algo': 'eq-priority-v1', 'priority_score': 75.2, 'priority_label': 'high',
  'priority_reasons': [{'code': 'distance_radius', 'text': 'Dekat titik pantau', 'values': {'radius_km': 50}}],
  'priority_components': {'distance': 1}, 'match_method': 'point_distance', 'match_distance_km': 0,
  'evaluated_at': stamp, 'created_at': stamp, 'read_at': null, 'is_simulated': true,
  'title': 'Gempa uji $seq', 'event_category': 'earthquake',
  'current_lifecycle_status': active ? 'current' : 'expired', 'present_as_active_alert': active,
};

class FakeLocal extends NoopLocalNotificationService {
  final alerts = <String>[], summaries = <int>[];
  int requests = 0, cancellations = 0;
  @override
  Future<NotificationPermissionState> requestPermission() async {
    requests++;
    return NotificationPermissionState.granted;
  }
  @override
  Future<void> showAlert(NotificationDto alert) async {
    alerts.add(localAlertTitle(alert.title, alert.isSimulated));
  }
  @override
  Future<void> showSummary({required int count, required String latestTitle,
      required bool isSimulated, String? eventId}) async {
    summaries.add(count);
  }
  @override
  Future<void> cancelAll() async { cancellations++; }
}

class Server extends http.BaseClient {
  final rows = <Json>[record(1)];
  final calls = <String>[];
  final streamHeaders = <String?>[];
  StreamController<List<int>>? wire;
  int streamAttempts = 0, openStreams = 0, rejectStreams = 0, syncStatus = 200;
  String conflict = 'CURSOR_OUT_OF_RANGE';
  bool rejectRead = false;
  int streamError = 503;
  int? retryAfter;
  Completer<void>? holdSync;
  int historyStatus = 200;
  int pageSize = 20;
  http.StreamedResponse json(Object data, [int status = 200]) =>
      http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(data))), status);
  http.StreamedResponse error(int status, String code) =>
      json({'code': code, 'message': code, 'request_id': 'test', 'details': null}, status);
  http.StreamedResponse wrapped(http.Response result) =>
      http.StreamedResponse(Stream.value(result.bodyBytes), result.statusCode);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    final query = request.url.queryParameters;
    if (path.contains('/notifications')) {
      expectSync(request.headers['Authorization'], 'Bearer memory-token');
      expectSync(request.followRedirects, isFalse);
    }
    if (path.endsWith('/sync')) {
      expectSync(openStreams, 0, reason: 'Sync must finish before opening SSE');
      final baseline = query['baseline'] == 'true';
      calls.add(baseline ? 'baseline' : 'sync');
      if (!baseline && holdSync != null) {
        final pending = holdSync!;
        holdSync = null;
        await pending.future;
      }
      if (!baseline && syncStatus != 200) {
        final result = error(syncStatus, conflict);
        syncStatus = 200;
        return result;
      }
      final since = baseline ? rows.length : int.parse(query['since_sequence']!);
      if (!baseline) expectSync(query['cursor_user_id'], owner);
      // One row per sync page exercises multi-page catch-up.
      final items = rows.skip(since).take(1).toList();
      return json({'items': items, 'cursor_user_id': owner, 'high_water_mark': rows.length,
        'next_sequence': since + items.length, 'has_more': since + items.length < rows.length, 'meta': meta});
    }
    if (path.endsWith('/stream')) {
      expectSync(openStreams, 0);
      expectSync(request.headers['Accept'], 'text/event-stream');
      expectSync(query['cursor_user_id'], owner);
      calls.add('stream');
      streamHeaders.add(request.headers['Last-Event-ID']);
      streamAttempts++;
      if (rejectStreams > 0) {
        rejectStreams--;
        return http.StreamedResponse(Stream.value(utf8.encode(jsonEncode({
          'code': streamError == 429 ? 'STREAM_LIMIT_REACHED' : 'SERVICE_UNAVAILABLE',
          'message': 'Kanal belum tersedia.', 'request_id': 'test', 'details': null,
        }))), streamError, headers: {if (retryAfter != null) 'retry-after': '$retryAfter'});
      }
      openStreams++;
      wire = StreamController<List<int>>(onCancel: () { openStreams--; });
      return http.StreamedResponse(wire!.stream, 200);
    }
    if (path.endsWith('/notifications')) {
      final offset = int.parse(query['offset']!);
      final unreadOnly = query['unread_only'] == 'true';
      calls.add('history/$offset/$unreadOnly');
      if (historyStatus != 200) return error(historyStatus, 'SERVICE_UNAVAILABLE');
      final filtered = rows.reversed.where((r) => !unreadOnly || r['read_at'] == null).toList();
      final more = filtered.length > offset + pageSize;
      return json({'items': filtered.skip(offset).take(pageSize).toList(),
        'unread_count': rows.where((r) => r['read_at'] == null).length, 'meta': meta,
        'page': {'offset': offset, 'limit': pageSize, 'has_more': more,
          'next_offset': more ? offset + pageSize : null}});
    }
    if (path.endsWith('/read')) {
      calls.add('read');
      expectSync(request.method, 'POST');
      expectSync(jsonDecode((request as http.Request).body), isEmpty);
      if (rejectRead) return error(503, 'SERVICE_UNAVAILABLE');
      final id = request.url.pathSegments.reversed.elementAt(1);
      rows.singleWhere((r) => r['id'] == id)['read_at'] = stamp;
      return wrapped(ok({'id': id, 'read_at': stamp}));
    }
    if (path.endsWith('/me/zone')) return wrapped(ok(zoneJson));
    if (path.endsWith('/health')) return wrapped(ok({'status': 'ok'}));
    if (path.endsWith('/me')) return wrapped(ok({...userJson, 'has_zone': true}));
    if (path.endsWith('/events') || path.endsWith('/reports')) return wrapped(emptyFeed());
    if (path.endsWith('/events/$quakeKey')) {
      calls.add('detail');
      return json(quakeDetail());
    }
    throw StateError('Unexpected request $path');
  }

  void sendFrame(String text) {
    final bytes = utf8.encode(text);
    wire!.add(bytes.sublist(0, 3));
    wire!.add(bytes.sublist(3));
  }
  void connected(int since) => sendFrame('event: connected\ndata: ${jsonEncode({
    'cursor_user_id': owner, 'since_sequence': since, 'high_water_mark': rows.length,
    'heartbeat_seconds': 20, 'is_simulated': true})}\n\n');
  void alert(Json row) => sendFrame('id: $owner:${row['sequence']}\nevent: alert\ndata: ${jsonEncode(row)}\n\n');
}

const timing = NotificationTimingConfig(
  heartbeatTimeout: Duration(seconds: 8), reconnectDelay: Duration(seconds: 1),
  pollingBackoff: [Duration(seconds: 2), Duration(seconds: 4)],
  sseProbeInterval: Duration(seconds: 7), jitterFraction: 0);

class Harness {
  Harness() {
    final repository = NotificationRepository(ApiClient(client: server, baseUrl: base, session: session));
    history = NotificationViewModel(repository, session);
    channel = NotificationCoordinator(repository, history, session, local, timing: timing);
  }
  final session = signedIn();
  final server = Server();
  final local = FakeLocal();
  late final NotificationViewModel history;
  late final NotificationCoordinator channel;
  void dispose() {
    channel.dispose();
    history.dispose();
    session.dispose();
    server.close();
  }
}

void main() {
  test('SSE accepts split Unicode, CR, LF, CRLF, comments and multiline data', () async {
    final bytes = utf8.encode(': keepalive\r\rretry: 3000\r\nevent: connected\r\ndata: siap\r\n\r\n'
        'id: $owner:2\nevent: alert\ndata: gunung 🌋\ndata: baris dua\n\n');
    final frames = await const SseParser().parse(Stream.fromIterable(bytes.map((b) => [b]))).toList();
    expect(frames.length, 3);
    expect(frames.first.isCommentOnly, isTrue);
    expect(frames[1].event, 'connected');
    expect(frames[1].retryMs, 3000);
    expect(frames.last.event, 'alert');
    expect(frames.last.id, '$owner:2');
    expect(frames.last.data, 'gunung 🌋\nbaris dua');
  });

  test('notification JSON, both feed shapes, immutable read and stable local IDs', () {
    final row = record(1);
    final history = NotificationHistoryFeedDto.fromJson({'items': [row], 'meta': meta,
      'unread_count': 12, 'page': {'limit': 1, 'offset': 0, 'next_offset': 1, 'has_more': true}});
    final sync = NotificationSyncFeedDto.fromJson({'items': [row], 'meta': meta,
      'high_water_mark': 12, 'next_sequence': 1, 'has_more': true, 'cursor_user_id': owner});
    final item = history.items.single;
    expect(sync.items.single.eventId, item.eventId);
    expect(sync.nextSequence, history.page.nextOffset);
    expect(sync.highWaterMark, history.unreadCount);
    expect(item.priorityComponents, {'distance': 1.0});
    expect(item.priorityReasons.single.values['radius_km'], 50);
    expect(item.evaluatedAt.isUtc, isTrue);
    expect(item.copyWithReadAt(DateTime.parse(stamp)).readAt, DateTime.parse(stamp));
    expect(item.readAt, isNull);
    final id = stableLocalNotificationId(item.id);
    expect(id, inInclusiveRange(2, 0x7fffffff));
    expect(stableLocalNotificationId(item.id), id);
    expect(stableLocalNotificationId(item.eventId), isNot(id));
    expect(localAlertTitle(item.title, false), item.title);
  });

  testWidgets('baseline history SSE, duplicate alert, paused silence, multi-page resume summary', (tester) async {
    final h = Harness();
    await tester.pump();
    expect(h.server.calls, ['baseline', 'history/0/false', 'stream']);
    expect(h.local.alerts, isEmpty);
    h.server.connected(1);
    final active = record(2);
    final expired = record(3, active: false);
    h.server.rows.addAll([active, expired]);
    h.server.alert(active);
    h.server.alert(active);
    h.server.alert(expired);
    await tester.pump();
    expect(h.channel.statusLabel, 'SSE aktif');
    expect(h.history.items.map((i) => i.sequence), [3, 2, 1]);
    expect(h.history.unreadCount, 3);
    expect(h.local.alerts, ['[SIMULASI] Gempa uji 2']);
    await h.channel.zoneUpdated();
    expect(h.channel.lastSequence, 3);
    h.channel.handleAppLifecycle(AppLifecycleState.paused);
    await tester.pump();
    expect(h.server.openStreams, 0);
    final count = h.server.calls.length;
    await tester.pump(const Duration(minutes: 6));
    expect(h.server.calls.length, count);
    expect(h.channel.statusLabel, 'Dijeda');
    h.server.rows.addAll([record(4), record(5, active: false), record(6)]);
    h.channel.handleAppLifecycle(AppLifecycleState.resumed);
    await tester.pump();
    expect(h.server.calls.skip(count), ['sync', 'sync', 'sync', 'stream']);
    expect(h.local.summaries, [2]);
    expect(h.local.alerts.length, 1);
    expect(h.server.streamHeaders.last, '$owner:6');
    h.dispose();
    await tester.pump();
  });

  testWidgets('keepalive extends timeout, reconnect, polling backoff and exclusive SSE probe', (tester) async {
    final h = Harness();
    await tester.pump();
    h.server.connected(1);
    await tester.pump(const Duration(seconds: 6));
    h.server.sendFrame(': keepalive\n\n');
    await tester.pump();
    await tester.pump(const Duration(seconds: 7));
    expect(h.channel.statusLabel, 'SSE aktif');
    h.server.rejectStreams = 1;
    await tester.pump(const Duration(seconds: 1));
    expect(h.channel.statusLabel, 'Menghubungkan');
    await tester.pump(const Duration(seconds: 1));
    expect(h.server.streamHeaders.last, '$owner:1');
    expect(h.channel.statusLabel, 'Polling');
    h.server.syncStatus = 503;
    await tester.pump(const Duration(seconds: 2));
    expect(h.channel.statusLabel, 'Offline');
    final count = h.server.calls.length;
    await tester.pump(const Duration(seconds: 3));
    expect(h.server.calls.length, count);
    await tester.pump(const Duration(seconds: 1));
    expect(h.channel.statusLabel, 'Polling');
    await tester.pump(const Duration(seconds: 1));
    h.server.connected(1);
    await tester.pump();
    expect(h.channel.statusLabel, 'SSE aktif');
    final attempts = h.server.calls.length;
    await tester.pump(const Duration(seconds: 3));
    expect(h.server.calls.length, attempts);
    unawaited(h.server.wire!.close());
    await tester.pump();
    expect(h.channel.statusLabel, 'Menghubungkan');
    h.dispose();
    await tester.pump();
  });

  testWidgets('stream 429 respects Retry-After and stream 401 ends session', (tester) async {
    final h = Harness();
    h.server.rejectStreams = 1;
    h.server.streamError = 429;
    h.server.retryAfter = 5;
    await tester.pump();
    expect(h.channel.notice, contains('5 detik'));
    expect(h.server.streamAttempts, 1);
    await tester.pump(const Duration(seconds: 4));
    expect(h.server.streamAttempts, 1);
    h.server.streamError = 401;
    h.server.rejectStreams = 1;
    await tester.pump(const Duration(seconds: 1));
    expect(h.server.streamAttempts, 2);
    expect(h.session.canNavigate, isFalse);
    expect(h.local.cancellations, 1);
    expect(h.history.items, isEmpty);
    await tester.pump(const Duration(minutes: 10));
    expect(h.server.streamAttempts, 2);
    h.dispose();
  });

  testWidgets('SSE probe waits for in-flight polling and paused sync cannot reopen SSE', (tester) async {
    final h = Harness();
    await tester.pump();
    h.server.rejectStreams = 1;
    unawaited(h.server.wire!.close());
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(h.channel.statusLabel, 'Polling');
    final poll = h.server.holdSync = Completer<void>();
    await tester.pump(const Duration(seconds: 2));
    final count = h.server.streamAttempts;
    await tester.pump(const Duration(seconds: 6));
    expect(h.server.streamAttempts, count);
    poll.complete();
    await tester.pump();
    expect(h.server.streamAttempts, count + 1);
    expect(h.server.openStreams, 1);
    h.channel.handleAppLifecycle(AppLifecycleState.paused);
    final resume = h.server.holdSync = Completer<void>();
    h.channel.handleAppLifecycle(AppLifecycleState.resumed);
    await tester.pump();
    h.channel.handleAppLifecycle(AppLifecycleState.inactive);
    resume.complete();
    await tester.pump();
    expect(h.server.openStreams, 0);
    expect(h.server.streamAttempts, count + 1);
    h.dispose();
  });

  testWidgets('failed refresh and load-more retain cached rows, count and next offset', (tester) async {
    final h = Harness();
    await tester.pump();
    h.server.pageSize = 1;
    h.server.rows.add(record(2));
    await h.history.refresh();
    expect(h.history.page!.nextOffset, 1);
    h.server.historyStatus = 503;
    await h.history.loadMore();
    expect(h.history.loadMoreError, isNotNull);
    expect(h.history.error, isNull);
    await h.history.refresh();
    expect(h.history.error, isNotNull);
    expect(h.history.items.single.sequence, 2);
    expect(h.history.unreadCount, 2);
    expect(h.history.page!.nextOffset, 1);
    h.server.historyStatus = 200;
    await h.history.loadMore();
    expect(h.history.items.map((item) => item.sequence), [2, 1]);
    h.dispose();
    await tester.pump();
  });

  for (final code in ['CURSOR_OUT_OF_RANGE', 'CURSOR_USER_MISMATCH']) {
    testWidgets('$code reloads baseline and history silently', (tester) async {
      final h = Harness();
      await tester.pump();
      h.channel.handleAppLifecycle(AppLifecycleState.hidden);
      h.server.rows.add(record(2));
      h.server.conflict = code;
      h.server.syncStatus = 409;
      h.channel.handleAppLifecycle(AppLifecycleState.resumed);
      await tester.pump();
      expect(h.server.calls.skip(3), ['sync', 'baseline', 'history/0/false', 'stream']);
      expect(h.channel.lastSequence, 2);
      expect(h.channel.notice, contains('ulang'));
      expect(h.history.items.length, 2);
      expect(h.local.alerts, isEmpty);
      h.dispose();
      await tester.pump();
    });
  }

  for (final cause in ['401', 'expiry', 'logout']) {
    testWidgets('$cause clears cursor and private history and stops retry', (tester) async {
      final h = Harness();
      await tester.pump();
      if (cause == '401') {
        h.channel.handleAppLifecycle(AppLifecycleState.inactive);
        h.server.syncStatus = 401;
        h.channel.handleAppLifecycle(AppLifecycleState.resumed);
      } else if (cause == 'expiry') {
        h.channel.handleAppLifecycle(AppLifecycleState.paused);
        await tester.pump(const Duration(hours: 2));
      } else {
        h.session.clear();
      }
      await tester.pump();
      expect(h.channel.cursorUserId, isNull);
      expect(h.channel.lastSequence, isNull);
      expect(h.history.items, isEmpty);
      expect(h.server.openStreams, 0);
      expect(h.local.cancellations, 1);
      final count = h.server.calls.length;
      await tester.pump(const Duration(minutes: 10));
      expect(h.server.calls.length, count);
      h.dispose();
    });
  }

  for (final failRead in [false, true]) {
    testWidgets('UI-05 360px 200%, permissions, pagination, filter, read failure=$failRead', (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final server = Server()..pageSize = 1..rejectRead = failRead;
      server.rows.add(record(2, active: false));
      final session = signedIn();
      final local = FakeLocal();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(SiagaApp(client: server, baseUrl: base, session: session,
        initialLocation: '/profile', localNotificationService: local,
        tileProvider: TestTileProvider(), textScaler: const TextScaler.linear(2)));
      await tester.pumpAndSettle();
      final context = tester.element(find.byType(ProfileScreen));
      final history = context.read<NotificationViewModel>();
      final router = GoRouter.of(context);
      expect(find.descendant(of: find.byType(NavigationBar), matching: find.text('2')), findsOneWidget);
      expect(find.text('SIMULASI'), findsOneWidget);
      expect(find.text('Kedaluwarsa'), findsOneWidget);
      expect(local.requests, 0);
      await tapVisible(tester, find.text('Aktifkan notifikasi'));
      expect(local.requests, 1);
      expect(find.text('Diizinkan'), findsOneWidget);
      await tapVisible(tester, find.text('Hanya belum dibaca'));
      expect(server.calls, contains('history/0/true'));
      await tapVisible(tester, find.text('Muat lebih banyak'));
      expect(server.calls, contains('history/1/true'));
      await tapVisible(tester, find.text('Gempa uji 1'));
      expect(find.byType(EventDetailScreen), findsOneWidget);
      expect(tester.widget<EventDetailScreen>(find.byType(EventDetailScreen)).eventId, quakeKey);
      expect(server.calls, containsAllInOrder(['read', 'detail']));
      expect(history.unreadCount, failRead ? 2 : 1);
      if (failRead) {
        expect(history.items.last.readAt, isNull);
        expect(history.notice, isNotNull);
      }
      router.pop();
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('Keluar'));
      expect(session.canNavigate, isFalse);
      expect(history.items, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      session.dispose();
    });
  }
}
