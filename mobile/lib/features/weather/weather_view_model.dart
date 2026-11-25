import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/session/session_coordinator.dart';
import '../zone/zone_view_model.dart';
import 'weather_dto.dart';
import 'weather_repository.dart';

class WeatherViewModel extends ChangeNotifier {
  WeatherViewModel(this.repository, this.session, this.zone) {
    _context = _currentContext;
    session.addListener(_sync);
    zone.addListener(_sync);
    if (session.canNavigate) unawaited(refresh());
  }

  final WeatherRepository repository;
  final SessionCoordinator session;
  final ZoneViewModel zone;
  CurrentWeatherDto? weather;
  int _request = 0;
  Future<void>? _pending;
  late (int, bool, int?) _context;
  (int, bool, int?) get _currentContext =>
      (session.generation, session.canNavigate, zone.savedZone?.zoneVersion);

  void _sync() {
    if (_context == _currentContext) return;
    _context = _currentContext;
    _request++;
    _pending = null;
    weather = null;
    notifyListeners();
    if (session.canNavigate) unawaited(refresh());
  }

  Future<void> refresh() {
    if (!session.canNavigate) return Future.value();
    return _pending ??= _fetch(++_request);
  }

  Future<void> _fetch(int request) async {
    CurrentWeatherDto? result;
    try {
      result = await repository.fetchCurrentWeather();
    } catch (_) {
      // Weather is optional. The feed remains usable offline.
    }
    if (request != _request) return;
    _pending = null;
    weather = result;
    notifyListeners();
  }

  @override
  void dispose() {
    _request++;
    session.removeListener(_sync);
    zone.removeListener(_sync);
    super.dispose();
  }
}
