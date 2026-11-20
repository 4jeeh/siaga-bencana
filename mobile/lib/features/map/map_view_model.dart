import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/network/api_envelope.dart';
import '../../core/session/session_coordinator.dart';
import '../events/event_dto.dart';
import '../zone/zone_view_model.dart';
import 'map_dto.dart';
import 'map_repository.dart';

class MapViewModel extends ChangeNotifier {
  MapViewModel(this.repository, this.session, this.zone, {
    this.debounceDuration = const Duration(milliseconds: 300),
  }) : _generation = session.generation, _zoneVersion = zone.savedZone?.zoneVersion {
    session.addListener(_syncContext);
    zone.addListener(_syncContext);
  }

  final MapRepository repository;
  final SessionCoordinator session;
  final ZoneViewModel zone;
  final Duration debounceDuration;
  Timer? _debounceTimer;
  int _generation, _requestCounter = 0;
  int? _zoneVersion;
  String? _bbox;
  (String?, String?, bool, bool)? _loadedQuery;
  bool hasInteracted = false;
  bool radiusOnly = true, includeReports = true, listMode = false;
  String? category;
  List<MapMarkerDto> items = const [];
  EventMetaDto? meta;
  DateTime? lastLoadedAt;
  String? error;
  bool loading = false, truncated = false, zoneRequired = false;

  void _clearResults() {
    _loadedQuery = null;
    items = const [];
    meta = null;
    lastLoadedAt = null;
    truncated = false;
  }

  void _syncContext() {
    final version = zone.savedZone?.zoneVersion;
    final reset = _generation != session.generation || !session.canNavigate;
    if (!reset && version == _zoneVersion) return;
    _generation = session.generation;
    _zoneVersion = version;
    _requestCounter++;
    _debounceTimer?.cancel();
    _clearResults();
    error = null;
    loading = zoneRequired = false;
    if (reset) {
      _bbox = category = null;
      hasInteracted = listMode = false;
      radiusOnly = includeReports = true;
    }
    if (hasInteracted && session.canNavigate) {
      unawaited(_load());
    } else {
      notifyListeners();
    }
  }

  Future<void> ensureInitialLoad({String? fallbackBbox}) async {
    hasInteracted = true;
    _bbox ??= fallbackBbox;
    if (!loading && meta == null) await _load();
  }

  void onViewportChanged(String bbox) {
    if (!session.canNavigate) return;
    hasInteracted = true;
    if (_bbox == bbox && (loading || _debounceTimer?.isActive == true || meta != null || error != null || zoneRequired)) return;
    _bbox = bbox;
    // Invalidate immediately, including the interval before the next GET starts.
    _requestCounter++;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounceDuration, () {
      if (_loadedQuery == (_bbox, category, radiusOnly, includeReports) && error == null) {
        loading = false;
        notifyListeners();
      } else {
        unawaited(_load());
      }
    });
  }

  Future<void> setRadiusOnly(bool value) async {
    if (radiusOnly == value) return;
    radiusOnly = value;
    await _load();
  }

  Future<void> setCategory(String? value) async {
    if (category == value) return;
    category = value;
    await _load();
  }

  Future<void> setIncludeReports(bool value) async {
    if (includeReports == value) return;
    includeReports = value;
    await _load();
  }

  Future<void> expandArea() {
    radiusOnly = false;
    category = null;
    includeReports = true;
    return _load();
  }

  Future<void> toggleListMode() async {
    listMode = !listMode;
    if (meta == null && !loading) {
      await _load();
    } else {
      notifyListeners();
    }
  }

  Future<void> retry() => _load();

  Future<void> _load() async {
    _debounceTimer?.cancel();
    if (!session.canNavigate) return;
    hasInteracted = true;
    final request = ++_requestCounter;
    final generation = session.generation;
    final version = zone.savedZone?.zoneVersion;
    bool current() => request == _requestCounter && generation == session.generation &&
        session.canNavigate && version == zone.savedZone?.zoneVersion;
    loading = true;
    error = null;
    zoneRequired = false;
    notifyListeners();
    try {
      final result = await repository.fetchMarkers(bbox: _bbox, category: category,
          radiusOnly: radiusOnly, includeReports: includeReports);
      if (!current()) return;
      if (result.meta.zoneVersion < (version ?? 0) ||
          result.meta.zoneVersion < (meta?.zoneVersion ?? 0)) {
        throw const ApiErrorEnvelope(code: 'STALE_ZONE', message: 'Data untuk zona terbaru belum tersedia.');
      }
      final seen = <String>{};
      items = List.unmodifiable(result.items.where((item) => seen.add(item.id)).take(result.cap));
      meta = result.meta;
      truncated = result.truncated;
      _loadedQuery = (_bbox, category, radiusOnly, includeReports);
      lastLoadedAt = DateTime.now().toUtc();
    } catch (failure) {
      if (!current()) return;
      if (failure is ApiErrorEnvelope && failure.code == 'ZONE_REQUIRED') {
        _clearResults();
        zoneRequired = true;
      } else {
        error = failure is ApiErrorEnvelope ? failure.message : 'Respons peta tidak valid. Coba lagi.';
      }
    } finally {
      if (current()) {
        loading = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _requestCounter++;
    _debounceTimer?.cancel();
    session.removeListener(_syncContext);
    zone.removeListener(_syncContext);
    super.dispose();
  }
}
