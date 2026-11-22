import 'package:flutter/foundation.dart';

import '../../core/network/api_envelope.dart';
import '../../core/session/session_coordinator.dart';
import '../events/event_dto.dart';
import '../events/event_repository.dart';
import '../zone/location_service.dart';
import '../zone/zone_dto.dart';
import '../zone/zone_view_model.dart';
import 'report_dto.dart';
import 'report_list_state.dart';
import 'report_photo_service.dart';
import 'report_repository.dart';
import 'report_text.dart';

class _SubmissionSnapshot {
  _SubmissionSnapshot(this.key, this.category, this.description, this.latitude, this.longitude, this.eventId, Uint8List? photo)
      : bytes = photo == null ? null : Uint8List.fromList(photo).asUnmodifiableView();
  final String key, category, description;
  final double latitude, longitude;
  final String? eventId;
  final Uint8List? bytes;
}

class ReportsViewModel extends ChangeNotifier {
  ReportsViewModel(this.reportRepository, this.eventRepository, this.session, this.zone, this.locationService, this.photoService)
      : _generation = session.generation, _version = zone.savedZone?.zoneVersion {
    session.addListener(_sessionChanged); zone.addListener(_zoneChanged);
  }
  final ReportRepository reportRepository;
  final EventRepository eventRepository;
  final SessionCoordinator session;
  final ZoneViewModel zone;
  final LocationService locationService;
  final ReportPhotoService photoService;
  final nearby = ReportListState(), mine = ReportListState();
  String? nearbyCategory, mineStatus;
  int _generation, _epoch = 0;
  int? _version;
  bool _nearbyActive = false;

  Future<void> loadNearby({bool more = false}) async {
    if (!session.canNavigate) return;
    _nearbyActive = true;
    await nearby.load((offset) => reportRepository.fetchReports(scope: 'nearby', category: nearbyCategory, offset: offset), notifyListeners,
      more: more, minimumZoneVersion: _version);
  }
  Future<void> loadMine({bool more = false}) async {
    if (session.canNavigate) await mine.load((offset) => reportRepository.fetchReports(scope: 'mine', status: mineStatus, offset: offset), notifyListeners, more: more);
  }
  void filterNearby(String? value) { nearbyCategory = value; nearby.clear(); loadNearby(); }
  void filterMine(String? value) { mineStatus = value; mine.clear(); loadMine(); }
  Future<void> refreshLists() async { await Future.wait([loadNearby(), loadMine()]); }

  String? draftCategory, draftEventId, photoError, locationError, submitError, contentChangedNotice;
  String draftDescription = '';
  String _normalizedDescription = '';
  int descriptionLength = 0;
  double? draftLatitude, draftLongitude;
  ProcessedReportPhoto? draftPhoto;
  ReportPhotoSource lastPhotoSource = ReportPhotoSource.gallery;
  bool submitting = false, picking = false, locating = false, canOpenSettings = false, conflict = false;
  _SubmissionSnapshot? _pendingSnapshot;
  Object? get pendingRetrySnapshot => _pendingSnapshot;
  String? get lockedKey => _pendingSnapshot?.key;
  bool get canSubmit => session.canNavigate && !submitting && !picking && !locating && !conflict && photoError == null &&
      reportCategories.containsKey(draftCategory) && descriptionLength >= 20 && descriptionLength <= 1000 && validCoordinates(draftLatitude, draftLongitude);

  void _edit() {
    if (_pendingSnapshot != null || conflict) contentChangedNotice = 'Isi berubah, akan menjadi laporan baru';
    _pendingSnapshot = null; conflict = false; submitError = null;
  }
  void setCategory(String? value) { if (!submitting && value != draftCategory) { _edit(); draftCategory = value; notifyListeners(); } }
  void setDescription(String value) {
    if (submitting || value == draftDescription) return;
    _edit();
    draftDescription = value;
    _normalizedDescription = normalizeReportText(value);
    descriptionLength = _normalizedDescription.runes.length;
    notifyListeners();
  }
  void setEvent(String? value) { if (!submitting && value != draftEventId) { _edit(); draftEventId = value; notifyListeners(); } }
  void applyInitialEventId(String id) { if (id.trim().isNotEmpty) setEvent(id); }
  void selectDraftPoint(double lat, double lon) {
    if (submitting || !validCoordinates(lat, lon)) return;
    final latitude = canonicalCoordinate(lat), longitude = canonicalLongitude(lon);
    if (draftLatitude != latitude || draftLongitude != longitude) _edit();
    draftLatitude = latitude; draftLongitude = longitude;
    locationError = null; canOpenSettings = false; notifyListeners();
  }
  Future<void> gps() async {
    if (locating || submitting) return;
    final epoch = _epoch;
    locating = true; locationError = null; canOpenSettings = false; notifyListeners();
    try {
      final point = await locationService.locateOnce();
      if (epoch != _epoch) return;
      if (!validCoordinates(point.latitude, point.longitude)) throw const LocationFailure('Koordinat GPS tidak valid.');
      selectDraftPoint(point.latitude, point.longitude);
    } catch (error) {
      if (epoch != _epoch) return;
      locationError = error is LocationFailure ? error.message : 'GPS tidak tersedia. Pilih titik manual.';
      canOpenSettings = error is LocationFailure && error.canOpenSettings;
    } finally { if (epoch == _epoch) { locating = false; notifyListeners(); } }
  }
  Future<void> openSettings() async {
    final epoch = _epoch;
    try {
      if (await locationService.openAppSettings() || epoch != _epoch) return;
    } catch (_) { if (epoch != _epoch) return; }
    locationError = 'Pengaturan tidak dapat dibuka. Pilih titik manual.';
    notifyListeners();
  }
  Future<void> pickPhoto(ReportPhotoSource source) async {
    if (picking || submitting) return;
    final epoch = _epoch;
    lastPhotoSource = source; picking = true; notifyListeners();
    try {
      final photo = await photoService.pickAndCompress(source);
      if (epoch == _epoch && photo != null) { _edit(); draftPhoto = photo; photoError = null; }
    } catch (error) {
      if (epoch == _epoch) photoError = error is PhotoProcessingFailure ? error.message : 'Foto tidak dapat diproses.';
    } finally { if (epoch == _epoch) { picking = false; notifyListeners(); } }
  }
  void removePhoto() { if (!submitting && !picking) { _edit(); draftPhoto = null; photoError = null; notifyListeners(); } }

  EventFeedDto? events;
  EventMetaDto? get eventsMeta => events?.meta;
  String? eventsError;
  bool eventsLoading = false;
  Future<void> loadEvents() async {
    if (eventsLoading) return;
    final epoch = _epoch;
    eventsLoading = true; eventsError = null; notifyListeners();
    try {
      final result = await eventRepository.fetchReportEventChoices();
      if (epoch == _epoch) events = result;
    } catch (error) { if (epoch == _epoch) eventsError = reportError(error); }
    finally { if (epoch == _epoch) { eventsLoading = false; notifyListeners(); } }
  }
  Future<bool> submit() async {
    if (!canSubmit) return false;
    final epoch = _epoch;
    final snap = _pendingSnapshot ??= _SubmissionSnapshot(generateUuidV4(), draftCategory!, _normalizedDescription, draftLatitude!, draftLongitude!, draftEventId, draftPhoto?.bytes);
    submitting = true; submitError = contentChangedNotice = null; notifyListeners();
    try {
      await reportRepository.submitReport(clientRequestId: snap.key, category: snap.category, description: snap.description, latitude: snap.latitude, longitude: snap.longitude, eventId: snap.eventId, photo: snap.bytes);
      if (epoch != _epoch) return false;
      _resetDraft(); notifyListeners(); refreshLists(); return true;
    } catch (error) {
      if (epoch != _epoch) return false;
      conflict = error is ApiErrorEnvelope && error.code == 'IDEMPOTENCY_CONFLICT';
      final retry = error is ApiErrorEnvelope && (error.statusCode == 503 || error.code == 'NETWORK_ERROR');
      if (!retry) _pendingSnapshot = null;
      submitError = [reportError(error), if (retry || conflict) 'Cek tab Saya sebelum mengirim lagi.'].join(' ');
      return false;
    } finally { if (epoch == _epoch) { submitting = false; notifyListeners(); } }
  }
  void _resetDraft() {
    _epoch++; _pendingSnapshot = null; draftCategory = draftEventId = photoError = locationError = submitError = contentChangedNotice = null;
    draftDescription = _normalizedDescription = ''; descriptionLength = 0; draftLatitude = draftLongitude = null; draftPhoto = null; events = null; eventsError = null;
    lastPhotoSource = ReportPhotoSource.gallery;
    conflict = locating = canOpenSettings = picking = submitting = eventsLoading = false;
  }
  void _sessionChanged() {
    if (_generation == session.generation) return;
    _generation = session.generation; _nearbyActive = false; nearbyCategory = mineStatus = null;
    _resetDraft(); nearby.clear(); mine.clear(); notifyListeners();
  }
  void _zoneChanged() {
    final version = zone.savedZone?.zoneVersion;
    if (version == _version) return;
    _version = version; nearby.clear();
    if (_nearbyActive && session.canNavigate) { loadNearby(); } else { notifyListeners(); }
  }
  @override
  void dispose() { _epoch++; nearby.clear(); mine.clear(); session.removeListener(_sessionChanged); zone.removeListener(_zoneChanged); super.dispose(); }
}
