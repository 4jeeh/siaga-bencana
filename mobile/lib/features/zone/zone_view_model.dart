import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/network/api_envelope.dart';
import '../../core/session/session_coordinator.dart';
import 'location_service.dart';
import 'zone_dto.dart';
import 'zone_repository.dart';

class ZoneViewModel extends ChangeNotifier {
  ZoneViewModel(this.repository, this.session, this.locationService)
      : _generation = session.generation {
    session.addListener(_sessionChanged);
  }
  final ZoneRepository repository;
  final SessionCoordinator session;
  final LocationService locationService;
  int _generation;
  int? _loadedGeneration;
  bool _disposed = false;
  bool loading = false;
  bool saving = false;
  bool locating = false;
  ZoneDto? savedZone;
  double? latitude;
  double? longitude;
  int radiusKm = 50;
  bool notifyEarthquake = true;
  bool notifyWeather = true;
  String? error;
  String? gpsMessage;
  bool canOpenSettings = false;

  bool get hasLoaded => _loadedGeneration == session.generation;
  bool get busy => loading || saving || locating;
  bool get canSave => !busy && session.isValid && session.verified &&
      validCoordinates(latitude, longitude);
  bool _current(int generation) => !_disposed && session.isValid &&
      session.verified && session.generation == generation;
  void _notify() { if (!_disposed) notifyListeners(); }

  void _sessionChanged() {
    if (_generation != session.generation) {
      _generation = session.generation;
      _loadedGeneration = null;
      savedZone = null;
      loading = saving = locating = false;
      resetDraft();
    }
    if (session.isValid && session.verified &&
        _loadedGeneration != session.generation && !loading) {
      unawaited(load());
    }
  }

  void resetDraft() {
    latitude = savedZone?.latitude;
    longitude = savedZone?.longitude;
    radiusKm = savedZone?.radiusKm ?? 50;
    notifyEarthquake = savedZone?.notifyEarthquake ?? true;
    notifyWeather = savedZone?.notifyWeather ?? true;
    error = gpsMessage = null;
    canOpenSettings = false;
    _notify();
  }

  Future<void> load() async {
    if (busy || !session.isValid || !session.verified) return;
    final generation = session.generation;
    loading = true;
    error = null;
    _notify();
    try {
      final zone = await repository.fetchZone();
      if (!_current(generation)) return;
      savedZone = zone;
      _loadedGeneration = generation;
      resetDraft();
    } catch (failure) {
      if (_current(generation)) error = _errorMessage(failure);
    } finally {
      if (_current(generation)) { loading = false; _notify(); }
    }
  }

  void selectPoint(double lat, double lon) {
    if (busy || !session.isValid || !session.verified || !validCoordinates(lat, lon)) return;
    latitude = canonicalCoordinate(lat);
    longitude = canonicalLongitude(lon);
    error = null;
    _notify();
  }

  void updatePreferences({int? radius, bool? earthquake, bool? weather}) {
    if (busy) return;
    if (radius != null && [25, 50, 100].contains(radius)) radiusKm = radius;
    notifyEarthquake = earthquake ?? notifyEarthquake;
    notifyWeather = weather ?? notifyWeather;
    _notify();
  }

  Future<void> locateOnce() async {
    if (busy || !session.isValid || !session.verified) return;
    final generation = session.generation;
    locating = true;
    gpsMessage = null;
    canOpenSettings = false;
    _notify();
    try {
      final point = await locationService.locateOnce();
      if (!_current(generation)) return;
      if (!validCoordinates(point.latitude, point.longitude)) {
        throw const LocationFailure('Koordinat GPS tidak valid. Pilih titik manual.');
      }
      latitude = canonicalCoordinate(point.latitude);
      longitude = canonicalLongitude(point.longitude);
      gpsMessage = 'Lokasi dipilih sekali. Tekan Simpan Zona Pantau untuk menyimpan.';
    } on LocationFailure catch (failure) {
      if (_current(generation)) {
        gpsMessage = failure.message;
        canOpenSettings = failure.canOpenSettings;
      }
    } on TimeoutException {
      if (_current(generation)) gpsMessage = 'GPS melebihi 10 detik. Coba lagi atau pilih titik manual.';
    } catch (_) {
      if (_current(generation)) gpsMessage = 'Lokasi tidak tersedia. Coba lagi atau pilih titik manual.';
    } finally {
      if (_current(generation)) { locating = false; _notify(); }
    }
  }

  Future<void> openSettings() async {
    final generation = session.generation;
    try {
      final opened = await locationService.openAppSettings();
      if (_current(generation) && !opened) {
        gpsMessage = 'Pengaturan tidak dapat dibuka. Pilih titik manual.';
        _notify();
      }
    } catch (_) {
      if (_current(generation)) {
        gpsMessage = 'Pengaturan tidak dapat dibuka. Pilih titik manual.';
        _notify();
      }
    }
  }

  Future<bool> save() async {
    if (!canSave) return false;
    final generation = session.generation;
    final request = ZoneUpdateRequest(
      latitude: latitude!, longitude: longitude!, radiusKm: radiusKm,
      notifyEarthquake: notifyEarthquake, notifyWeather: notifyWeather,
    );
    saving = true;
    error = null;
    _notify();
    try {
      final zone = await repository.saveZone(request);
      if (!_current(generation)) return false;
      savedZone = zone;
      _loadedGeneration = generation;
      resetDraft();
      return session.markZoneSaved(generation);
    } catch (failure) {
      if (_current(generation)) error = _errorMessage(failure);
      return false;
    } finally {
      if (_current(generation)) { saving = false; _notify(); }
    }
  }

  String _errorMessage(Object failure) => failure is ApiErrorEnvelope
      ? failure.message : 'Respons zona tidak valid. Coba lagi.';

  @override
  void dispose() {
    _disposed = true;
    session.removeListener(_sessionChanged);
    super.dispose();
  }
}
