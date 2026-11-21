import 'package:flutter/foundation.dart';

import '../../core/network/api_envelope.dart';
import '../../core/session/session_coordinator.dart';
import '../events/event_dto.dart';
import '../events/event_repository.dart';
import '../zone/zone_view_model.dart';

class EventDetailViewModel extends ChangeNotifier {
  EventDetailViewModel(this.repository, this.session, this.zone)
    : _generation = session.generation,
      _zoneVersion = zone.savedZone?.zoneVersion {
    session.addListener(_onSession);
    zone.addListener(_onZone);
  }

  final EventRepository repository;
  final SessionCoordinator session;
  final ZoneViewModel zone;
  int _generation;
  int? _zoneVersion;
  int _requestCounter = 0;

  String? currentEventId;
  EventDetailDto? detail;
  EventMetaDto? meta;
  DateTime? lastLoadedAt;
  String? error;
  bool initialLoading = false;
  bool refreshing = false;
  bool notFound = false;
  bool zoneRequired = false;

  void _clear() {
    detail = null;
    meta = null;
    lastLoadedAt = null;
    error = null;
    notFound = false;
    zoneRequired = false;
  }

  void _onSession() {
    if (session.generation == _generation && session.canNavigate) return;
    _generation = session.generation;
    _requestCounter++;
    currentEventId = null;
    initialLoading = refreshing = false;
    _clear();
    notifyListeners();
  }

  void _onZone() {
    final version = zone.savedZone?.zoneVersion;
    if (_zoneVersion == version) return;
    _zoneVersion = version;
    final id = currentEventId;
    if (id != null && session.canNavigate && session.generation == _generation) {
      load(id);
    }
  }

  Future<void> refresh() async {
    final id = currentEventId;
    if (id != null) await load(id, refresh: true);
  }

  Future<void> load(String eventId, {bool refresh = false}) async {
    if (!session.canNavigate) return;
    final request = ++_requestCounter;
    final generation = session.generation;
    bool current() =>
        request == _requestCounter &&
        session.generation == generation &&
        currentEventId == eventId &&
        session.canNavigate;

    if (!refresh || currentEventId != eventId) _clear();
    currentEventId = eventId;
    initialLoading = detail == null;
    refreshing = !initialLoading;
    error = null;
    notFound = zoneRequired = false;
    notifyListeners();
    try {
      final result = await repository.fetchEventDetail(eventId);
      if (!current()) return;
      if (result.meta.zoneVersion < (zone.savedZone?.zoneVersion ?? 0)) {
        error = 'Detail untuk zona terbaru belum tersedia.';
      } else if (result.data.id != eventId) {
        throw const FormatException('Unexpected event ID');
      } else {
        detail = result.data;
        meta = result.meta;
        lastLoadedAt = DateTime.now().toUtc();
      }
    } on ApiErrorEnvelope catch (e) {
      if (!current()) return;
      notFound = e.statusCode == 404 || e.code == 'RESOURCE_NOT_FOUND';
      zoneRequired = e.statusCode == 409 || e.code == 'ZONE_REQUIRED';
      error = e.message;
    } on FormatException {
      if (current()) error = 'Respons detail tidak valid.';
    } on ArgumentError {
      if (current()) error = 'ID kejadian tidak valid.';
    } finally {
      if (current()) {
        initialLoading = refreshing = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _requestCounter++;
    session.removeListener(_onSession);
    zone.removeListener(_onZone);
    super.dispose();
  }
}
