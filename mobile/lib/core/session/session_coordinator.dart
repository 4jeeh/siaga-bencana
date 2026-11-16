import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../features/auth/auth_dto.dart';

class SessionCoordinator extends ChangeNotifier {
  SessionCoordinator({DateTime Function()? now})
    : _now = now ?? (() => DateTime.now().toUtc());
  final DateTime Function() _now;
  String? _token;
  DateTime? expiresAt;
  UserDto? user;
  String? message;
  String? pendingDestination;
  bool verified = false;
  int generation = 0;
  Timer? _expiryTimer;
  String? get token => isValid ? _token : null;
  bool get isValid =>
      _token != null && expiresAt != null && _now().isBefore(expiresAt!);
  bool get canNavigate => isValid && verified && user?.hasZone == true;
  void establish(AuthData auth) {
    _expiryTimer?.cancel();
    generation++;
    _token = auth.accessToken;
    expiresAt = auth.expiresAt;
    user = auth.user;
    verified = false;
    message = null;
    final remaining = expiresAt!.difference(_now());
    if (remaining <= Duration.zero) {
      clear(expired: true);
      return;
    }
    _expiryTimer = Timer(remaining, () => clear(expired: true));
    notifyListeners();
  }

  void confirm(UserDto current, int expectedGeneration) {
    if (generation != expectedGeneration || !isValid) return;
    user = current;
    verified = true;
    notifyListeners();
  }

  void checkExpiry() {
    if (_token != null && !isValid) clear(expired: true);
  }

  void clear({bool expired = false}) {
    generation++;
    _expiryTimer?.cancel();
    _expiryTimer = null;
    _token = null;
    user = null;
    expiresAt = null;
    verified = false;
    pendingDestination = null;
    message = expired ? 'Sesi berakhir, masuk kembali.' : null;
    notifyListeners();
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    super.dispose();
  }
}
