import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/widgets.dart';

import '../../core/network/api_envelope.dart';
import '../../core/network/sse_client.dart';
import '../../core/session/session_coordinator.dart';
import 'local_notification_service.dart';
import 'notification_dto.dart';
import 'notification_repository.dart';
import 'notification_view_model.dart';

enum NotificationChannelStatus { idle, connecting, sseActive, polling, paused, offline }

class NotificationTimingConfig {
  const NotificationTimingConfig({
    this.heartbeatTimeout = const Duration(seconds: 45),
    this.reconnectDelay = const Duration(seconds: 3),
    this.pollingBackoff = const [Duration(seconds: 60), Duration(seconds: 120),
      Duration(seconds: 240), Duration(seconds: 300)],
    this.sseProbeInterval = const Duration(minutes: 5), this.jitterFraction = 0.1,
  }) : assert(jitterFraction >= 0 && jitterFraction < 1);
  final Duration heartbeatTimeout, reconnectDelay, sseProbeInterval;
  final List<Duration> pollingBackoff;
  final double jitterFraction;
}

class NotificationCoordinator extends ChangeNotifier {
  NotificationCoordinator(this.repository, this.vm, this.session, this.local, {
    this.enabled = true, this.timing = const NotificationTimingConfig(),
    this._resumed = true, Random? random,
  }) : _random = random ?? Random(), _generation = session.generation {
    session.addListener(_sessionChanged);
    _sessionChanged();
  }
  final NotificationRepository repository;
  final NotificationViewModel vm;
  final SessionCoordinator session;
  final LocalNotificationService local;
  final NotificationTimingConfig timing;
  final bool enabled;
  final Random _random;
  bool _resumed, _disposed = false, _running = false, _pollBusy = false, _probeDue = false;
  int _generation, _epoch = 0, _failures = 0, _pollStep = 0;
  bool _recoveringCursor = false;
  final _seenIds = <String>{};
  Timer? _heartbeat, _retry, _poll, _probe;
  SseStreamHandle? _handle;
  StreamSubscription<SseFrame>? _subscription;

  NotificationChannelStatus status = NotificationChannelStatus.idle;
  DateTime? lastReceivedAt;
  String? cursorUserId, notice;
  int? lastSequence;
  bool isSimulated = false;
  String get statusLabel => switch (status) {
    NotificationChannelStatus.sseActive => 'SSE aktif',
    NotificationChannelStatus.polling => 'Polling',
    NotificationChannelStatus.connecting => 'Menghubungkan',
    NotificationChannelStatus.offline => 'Offline',
    _ => 'Dijeda',
  };

  void _sessionChanged() {
    final changed = _generation != session.generation;
    if (changed || (!session.canNavigate && (_running || cursorUserId != null))) {
      _generation = session.generation;
      _stop();
      cursorUserId = notice = null;
      lastReceivedAt = null;
      lastSequence = null;
      isSimulated = _recoveringCursor = false;
      _seenIds.clear();
      _failures = _pollStep = 0;
      unawaited(local.cancelAll().catchError((Object _) {}));
      _set(NotificationChannelStatus.idle);
    }
    if (enabled && session.canNavigate && _resumed && !_running) {
      _running = true;
      unawaited(_connect(_epoch));
    }
  }

  void handleAppLifecycle(AppLifecycleState state) {
    final resumed = state == AppLifecycleState.resumed;
    if (resumed == _resumed) return;
    _resumed = resumed;
    if (resumed) {
      _sessionChanged();
    } else {
      _stop();
      _set(NotificationChannelStatus.paused);
    }
  }

  Future<void> zoneUpdated() async {
    if (enabled && cursorUserId != null && session.canNavigate) await vm.refresh();
  }

  bool _valid(int epoch) => !_disposed && _running && epoch == _epoch &&
      _resumed && session.canNavigate && session.generation == _generation;
  void _set(NotificationChannelStatus value) {
    status = value;
    if (!_disposed) notifyListeners();
  }
  Duration _jitter(Duration delay) => Duration(microseconds:
      (delay.inMicroseconds * (1 + (_random.nextDouble() * 2 - 1) * timing.jitterFraction)).round());

  void _closeChannel() {
    _epoch++;
    _heartbeat?.cancel();
    _retry?.cancel();
    _probe?.cancel();
    _poll?.cancel();
    _pollBusy = _probeDue = false;
    _handle?.close();
    _handle = null;
    repository.cancelStream();
    unawaited(_subscription?.cancel());
    _subscription = null;
  }

  void _stop() {
    _running = false;
    _closeChannel();
  }

  Future<void> _prepare(int epoch) async {
    if (cursorUserId != null) {
      await _catchUp(epoch);
      return;
    }
    final baseline = await repository.baseline();
    if (!_valid(epoch)) return;
    _owner(baseline.cursorUserId);
    cursorUserId = baseline.cursorUserId;
    lastSequence = baseline.highWaterMark;
    isSimulated = baseline.meta.isSimulated;
    await vm.loadInitial(resetSnapshot: true);
  }

  void _owner(String owner) {
    if (owner != session.user?.id) {
      throw const ApiErrorEnvelope(statusCode: 409, code: 'CURSOR_USER_MISMATCH',
          message: 'Cursor bukan milik akun aktif.');
    }
  }

  Future<void> _connect(int epoch) async {
    _set(NotificationChannelStatus.connecting);
    final replay = cursorUserId != null;
    try {
      await _prepare(epoch);
      if (!_valid(epoch)) return;
      final handle = await repository.openStream(sinceSequence: lastSequence!,
          cursorUserId: cursorUserId!, lastEventId: replay ? '$cursorUserId:$lastSequence' : null);
      if (!_valid(epoch)) {
        handle.close();
        return;
      }
      _handle = handle;
      _armHeartbeat(epoch);
      _subscription = handle.stream.listen((frame) {
        if (!_valid(epoch)) return;
        try {
          _receive(epoch, frame);
        } catch (error) {
          _failed(epoch, error);
        }
      }, onError: (Object error) => _failed(epoch, error),
        onDone: () => _failed(epoch, null));
    } catch (error) {
      _failed(epoch, error);
    }
  }

  void _armHeartbeat(int epoch) {
    _heartbeat?.cancel();
    _heartbeat = Timer(timing.heartbeatTimeout, () => _failed(epoch, null));
  }

  void _receive(int epoch, SseFrame frame) {
    _armHeartbeat(epoch);
    lastReceivedAt = DateTime.now();
    if (frame.isCommentOnly || frame.event == 'heartbeat') {
      notifyListeners();
      return;
    }
    if (frame.event == 'connected') {
      final data = SseConnectedPayload.fromJson(jsonDecode(frame.data) as Map<String, dynamic>);
      _owner(data.cursorUserId);
      if (data.sinceSequence != lastSequence) throw const FormatException('Cursor SSE berbeda.');
      isSimulated = data.isSimulated;
      _failures = _pollStep = 0;
      if (!_recoveringCursor) notice = null;
      _recoveringCursor = false;
      _set(NotificationChannelStatus.sseActive);
    }
    if (frame.event == 'alert') {
      final item = NotificationDto.fromJson(jsonDecode(frame.data) as Map<String, dynamic>);
      if (frame.id != '$cursorUserId:${item.sequence}' || item.sequence > lastSequence! + 1) {
        throw const FormatException('Urutan SSE tidak sesuai.');
      }
      if (item.sequence <= lastSequence!) return;
      vm.ingestItems([item]);
      final fresh = _seenIds.add(item.id);
      lastSequence = item.sequence;
      if (fresh && item.presentAsActiveAlert) unawaited(_present([item], epoch));
      notifyListeners();
    }
  }

  Future<void> _catchUp(int epoch) async {
    // Commit the cursor after the full batch so a failed later page can be replayed.
    var since = lastSequence!;
    final batch = <NotificationDto>[];
    while (_valid(epoch)) {
      final feed = await repository.sync(sinceSequence: since, cursorUserId: cursorUserId!);
      if (!_valid(epoch)) return;
      _owner(feed.cursorUserId);
      isSimulated = feed.meta.isSimulated;
      for (final item in feed.items) {
        if (item.sequence != ++since) throw const FormatException('Urutan sync tidak sesuai.');
        batch.add(item);
      }
      if (feed.nextSequence != since || (feed.hasMore && feed.items.isEmpty)) {
        throw const FormatException('Cursor sync tidak maju.');
      }
      if (!feed.hasMore) break;
    }
    if (!_valid(epoch)) return;
    vm.ingestItems(batch);
    final active = [for (final item in batch)
      if (_seenIds.add(item.id) && item.presentAsActiveAlert) item];
    lastSequence = since;
    lastReceivedAt = DateTime.now();
    await _present(active, epoch);
  }

  Future<void> _present(List<NotificationDto> active, int epoch) async {
    if (active.isEmpty || !_valid(epoch)) return;
    try {
      if (active.length == 1) {
        await local.showAlert(active.single);
      } else {
        await local.showSummary(count: active.length, latestTitle: active.last.title,
          eventId: active.last.eventId, isSimulated: active.any((item) => item.isSimulated));
      }
    } catch (_) {
      if (_valid(epoch)) {
        notice = 'Notifikasi lokal gagal ditampilkan. Periksa riwayat.';
        notifyListeners();
      }
    }
  }

  bool _recover(Object? error) {
    if (error is! ApiErrorEnvelope) return false;
    notice = error.retryAfter == null ? error.message :
        '${error.message} Coba lagi setelah ${error.retryAfter} detik.';
    if (error.statusCode == 401) {
      session.clear(expired: true);
      return true;
    }
    if (error.statusCode != 409 ||
        !{'CURSOR_OUT_OF_RANGE', 'CURSOR_USER_MISMATCH'}.contains(error.code)) {
      return false;
    }
    cursorUserId = null;
    lastSequence = null;
    _seenIds.clear();
    notice = 'Menyinkronkan ulang riwayat notifikasi.';
    if (_recoveringCursor) return false;
    _recoveringCursor = true;
    _closeChannel();
    unawaited(_connect(_epoch));
    return true;
  }

  Duration _delay(Duration base, Object? error) {
    final delay = _jitter(base);
    final minimum = Duration(seconds: error is ApiErrorEnvelope ? error.retryAfter ?? 0 : 0);
    return delay < minimum ? minimum : delay;
  }

  void _failed(int epoch, Object? error) {
    if (!_valid(epoch) || _recover(error)) return;
    _closeChannel();
    final next = _epoch;
    if (++_failures == 1) {
      _set(NotificationChannelStatus.connecting);
      _retry = Timer(_delay(timing.reconnectDelay, error), () => _connect(next));
    } else {
      _set(NotificationChannelStatus.polling);
      _schedulePoll(next, error);
      _scheduleProbe(next, error);
    }
  }

  void _scheduleProbe(int epoch, Object? error) {
    final minimum = Duration(seconds: error is ApiErrorEnvelope ? error.retryAfter ?? 0 : 0);
    final interval = timing.sseProbeInterval;
    _probe?.cancel();
    _probeDue = false;
    _probe = Timer(interval < minimum ? minimum : interval, () {
      if (!_valid(epoch)) return;
      if (_pollBusy) {
        _probeDue = true;
      } else {
        _startProbe();
      }
    });
  }

  void _startProbe() {
    _closeChannel();
    unawaited(_connect(_epoch));
  }
  void _schedulePoll(int epoch, Object? error) {
    _poll = Timer(_delay(timing.pollingBackoff[_pollStep], error), () => _pollOnce(epoch));
  }
  Future<void> _pollOnce(int epoch) async {
    if (!_valid(epoch)) return;
    _pollBusy = true;
    Object? failure;
    try {
      await _prepare(epoch);
      if (!_valid(epoch)) return;
      _pollStep = 0;
      _set(NotificationChannelStatus.polling);
    } catch (error) {
      if (!_valid(epoch) || _recover(error)) return;
      failure = error;
      if (error is ApiErrorEnvelope && error.retryAfter != null) _scheduleProbe(epoch, error);
      _pollStep = min(_pollStep + 1, timing.pollingBackoff.length - 1);
      _set(NotificationChannelStatus.offline);
    }
    if (!_valid(epoch)) return;
    _pollBusy = false;
    if (_probeDue) {
      _startProbe();
    } else {
      _schedulePoll(epoch, failure);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _stop();
    session.removeListener(_sessionChanged);
    super.dispose();
  }
}
