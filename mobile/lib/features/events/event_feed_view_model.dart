import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/network/api_envelope.dart';
import '../../core/session/session_coordinator.dart';
import '../zone/zone_view_model.dart';
import 'event_dto.dart';
import 'event_repository.dart';

class EventFeedViewModel extends ChangeNotifier {
  EventFeedViewModel(this.repository, this.session, this.zone)
      : _generation = session.generation,
        _active = session.canNavigate,
        _zoneVersion = zone.savedZone?.zoneVersion {
    session.addListener(_syncContext);
    zone.addListener(_syncContext);
  }

  final EventRepository repository;
  final SessionCoordinator session;
  final ZoneViewModel zone;
  int _generation;
  int _requestCounter = 0;
  int? _zoneVersion;
  int _latestFeedVersion = 0;
  bool _active;

  bool _radiusOnly = true;
  String? _category;
  String _sort = 'recent';
  String _weatherStatus = 'active';
  bool get radiusOnly => _radiusOnly;
  String? get category => _category;
  String get sort => _sort;
  String get weatherStatus => _weatherStatus;

  List<EventSummaryDto> items = const [];
  PageDto? page;
  EventMetaDto? meta;
  DateTime? lastLoadedAt;
  String? error;
  String? loadMoreError;
  bool initialLoading = false;
  bool refreshing = false;
  bool loadingMore = false;
  bool zoneRequired = false;

  void _clearCache() {
    _requestCounter++;
    items = const [];
    page = null;
    meta = null;
    lastLoadedAt = null;
    error = loadMoreError = null;
    initialLoading = refreshing = loadingMore = zoneRequired = false;
  }

  void _syncContext() {
    final active = session.canNavigate;
    final version = zone.savedZone?.zoneVersion;
    if (_generation == session.generation && active == _active && version == _zoneVersion) return;
    if (_generation != session.generation || !active) {
      _latestFeedVersion = 0;
      _radiusOnly = true;
      _category = null;
      _sort = 'recent';
      _weatherStatus = 'active';
    }
    _generation = session.generation;
    _active = active;
    _zoneVersion = version;
    _clearCache();
    if (active) {
      unawaited(refresh());
    } else {
      notifyListeners();
    }
  }

  Future<void> setFilters({
    required String? category,
    required bool radiusOnly,
    String? sort,
    String? weatherStatus,
  }) async {
    final order = category == 'earthquake' ? sort ?? this.sort : 'recent';
    final status = radiusOnly || category == 'earthquake'
        ? 'active' : weatherStatus ?? this.weatherStatus;
    if (category == this.category && radiusOnly == this.radiusOnly &&
        order == this.sort && status == this.weatherStatus) {
      return;
    }
    _category = category;
    _radiusOnly = radiusOnly;
    _sort = order;
    _weatherStatus = status;
    _clearCache();
    await refresh();
  }

  Future<void> refresh() => _load();
  Future<void> loadMore() async {
    final offset = page?.nextOffset;
    if (offset == null || page?.hasMore != true || loadingMore || refreshing || initialLoading) return;
    await _load(offset: offset);
  }

  Future<void> _load({int? offset}) async {
    if (!session.canNavigate) return;
    final request = ++_requestCounter;
    final generation = session.generation;
    bool current() => request == _requestCounter && generation == session.generation && session.canNavigate;
    loadingMore = offset != null;
    initialLoading = !loadingMore && meta == null;
    refreshing = !loadingMore && !initialLoading;
    if (!loadingMore) error = null;
    loadMoreError = null;
    zoneRequired = false;
    notifyListeners();
    try {
      final result = await repository.fetchEvents(category: category, radiusOnly: radiusOnly,
        sort: sort, weatherStatus: weatherStatus, offset: offset ?? 0);
      if (!current()) return;
      final version = result.meta.zoneVersion;
      if (version < (_zoneVersion ?? 0) || version < _latestFeedVersion) {
        throw const ApiErrorEnvelope(code: 'STALE_ZONE', message: 'Data untuk zona terbaru belum tersedia.');
      }
      _latestFeedVersion = version;
      if (offset != null && version != meta?.zoneVersion) {
        _clearCache();
        await refresh();
        return;
      }
      final seen = <String>{};
      final combined = offset == null ? result.items : items.followedBy(result.items);
      items = List.unmodifiable(combined.where((item) => seen.add(item.id)));
      meta = result.meta;
      page = result.page;
      lastLoadedAt = DateTime.now().toUtc();
    } catch (failure) {
      if (!current()) return;
      final message = failure is ApiErrorEnvelope ? failure.message : 'Respons feed tidak valid. Coba lagi.';
      if (failure is ApiErrorEnvelope && failure.code == 'ZONE_REQUIRED') {
        _clearCache();
        zoneRequired = true;
        notifyListeners();
      } else if (offset == null) {
        error = message;
      } else {
        loadMoreError = message;
      }
    } finally {
      if (current()) {
        initialLoading = refreshing = loadingMore = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _requestCounter++;
    session.removeListener(_syncContext);
    zone.removeListener(_syncContext);
    super.dispose();
  }
}
