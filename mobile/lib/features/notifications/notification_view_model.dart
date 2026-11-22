import 'package:flutter/foundation.dart';

import '../../core/network/api_envelope.dart';
import '../../core/session/session_coordinator.dart';
import '../events/event_dto.dart';
import 'notification_dto.dart';
import 'notification_repository.dart';

class NotificationViewModel extends ChangeNotifier {
  NotificationViewModel(this.repository, this.session) : _generation = session.generation {
    session.addListener(_sessionChanged);
  }
  final NotificationRepository repository;
  final SessionCoordinator session;
  int _generation;
  int _request = 0;
  int _historyThrough = 0;
  bool _disposed = false;
  List<NotificationDto> items = [];
  int unreadCount = 0;
  ApiMeta? meta;
  PageDto? page;
  bool unreadOnly = false, initialLoading = false, refreshing = false, loadingMore = false;
  String? error, loadMoreError, notice;
  DateTime? lastLoadedAt;
  final _known = <String, NotificationDto>{};
  final _duringLoad = <String, NotificationDto>{};

  void _sessionChanged() {
    if (_generation == session.generation && session.canNavigate) return;
    _generation = session.generation;
    _request++;
    items = [];
    _known.clear();
    _duringLoad.clear();
    page = null;
    meta = null;
    lastLoadedAt = null;
    error = loadMoreError = notice = null;
    unreadCount = _historyThrough = 0;
    unreadOnly = initialLoading = refreshing = loadingMore = false;
    notifyListeners();
  }

  Future<void> setUnreadOnly(bool value) async {
    if (unreadOnly == value) return;
    unreadOnly = value;
    page = null;
    _display(_known.values);
    await loadInitial();
  }

  Future<void> loadInitial({bool resetSnapshot = false}) => _load(more: false, resetSnapshot: resetSnapshot);
  Future<void> refresh() => _load(more: false);
  Future<void> loadMore() async {
    if (loadingMore || initialLoading || refreshing || page?.nextOffset == null) return;
    await _load(more: true);
  }

  Future<void> _load({required bool more, bool resetSnapshot = false}) async {
    if (_disposed || !session.canNavigate) return;
    final request = ++_request;
    _duringLoad.clear();
    loadingMore = more;
    initialLoading = !more && items.isEmpty;
    refreshing = !more && !initialLoading;
    error = loadMoreError = null;
    notifyListeners();
    try {
      final feed = await repository.history(offset: more ? page!.nextOffset! : 0, unreadOnly: unreadOnly);
      if (!_current(request)) return;
      if (resetSnapshot) {
        _known.clear();
        _historyThrough = 0;
      }
      final visible = {if (more) for (final item in items) item.id: item};
      for (final item in feed.items) {
        final readAt = _known[item.id]?.readAt;
        visible[item.id] = _known[item.id] = item.readAt == null && readAt != null
            ? item.copyWithReadAt(readAt) : item;
      }
      final newest = feed.items.isEmpty ? 0 : feed.items.first.sequence;
      if (!more && newest > _historyThrough) _historyThrough = newest;
      final serverById = {for (final item in feed.items) item.id: item};
      // A later page has no high-water mark for the first page. Preserve
      // live count changes received while this offset request was in flight.
      final keepLiveCount = more && _duringLoad.isNotEmpty;
      if (!keepLiveCount) unreadCount = feed.unreadCount;
      for (final item in _duringLoad.values) {
        final server = serverById[item.id];
        if (server == null && item.sequence > newest && item.readAt == null && !more) unreadCount++;
        if (!keepLiveCount && server != null && server.readAt == null && item.readAt != null && unreadCount > 0) unreadCount--;
        visible[item.id] = _known[item.id] = item;
      }
      _display(visible.values);
      page = feed.page;
      meta = feed.meta;
      lastLoadedAt = DateTime.now();
    } catch (failure) {
      if (!_current(request)) return;
      if (more) {
        loadMoreError = _message(failure);
      } else {
        error = _message(failure);
      }
    } finally {
      if (_current(request)) {
        initialLoading = refreshing = loadingMore = false;
        _duringLoad.clear();
        notifyListeners();
      }
    }
  }

  bool _current(int request) => !_disposed && session.canNavigate && request == _request;
  String _message(Object failure) => failure is ApiErrorEnvelope
      ? failure.message : 'Riwayat notifikasi gagal diperbarui.';
  void _display(Iterable<NotificationDto> source) {
    items = source.where((item) => !unreadOnly || item.readAt == null).toList()
      ..sort((a, b) => b.sequence.compareTo(a.sequence));
  }

  void ingestItems(List<NotificationDto> incoming) {
    if (_disposed || !session.canNavigate || incoming.isEmpty) return;
    final visible = {for (final item in items) item.id: item};
    for (var item in incoming) {
      final old = _known[item.id];
      if (old?.readAt != null && item.readAt == null) item = item.copyWithReadAt(old!.readAt!);
      if (item.readAt == null && old == null && item.sequence > _historyThrough) unreadCount++;
      if (item.readAt != null && old != null && old.readAt == null && unreadCount > 0) unreadCount--;
      visible[item.id] = _known[item.id] = item;
      if (initialLoading || refreshing || loadingMore) _duringLoad[item.id] = item;
    }
    final previousLength = items.length;
    _display(visible.values);
    final currentPage = page;
    final nextOffset = currentPage?.nextOffset;
    if (currentPage != null && nextOffset != null) {
      page = PageDto(limit: currentPage.limit, offset: currentPage.offset,
          nextOffset: (nextOffset + items.length - previousLength).clamp(0, nextOffset + items.length),
          hasMore: currentPage.hasMore);
    }
    notifyListeners();
  }

  Future<void> markRead(NotificationDto item) async {
    if (_disposed || !session.canNavigate) return;
    final generation = session.generation;
    try {
      final data = await repository.markRead(item.id);
      if (data.id != item.id) throw const FormatException('ID notifikasi berbeda.');
      if (_disposed || generation != session.generation || !session.canNavigate) return;
      notice = null;
      ingestItems([(_known[item.id] ?? item).copyWithReadAt(data.readAt)]);
    } catch (failure) {
      if (_disposed || generation != session.generation || !session.canNavigate) return;
      notice = 'Gagal menandai dibaca. ${_message(failure)}';
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    session.removeListener(_sessionChanged);
    super.dispose();
  }
}
