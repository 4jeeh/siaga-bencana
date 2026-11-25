import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../features/auth/auth_dto.dart';
import 'session_store.dart';

class SessionCoordinator extends ChangeNotifier {
  SessionCoordinator({DateTime Function()? now, SessionStore? store})
    : store = store ?? MemorySessionStore(), _now = now ?? (() => DateTime.now().toUtc());
  final DateTime Function() _now;
  final SessionStore store;
  bool restoring = false;
  bool _rememberOnConfirm = true;
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
  bool get canNavigate => !restoring && isValid && verified && user?.hasZone == true;
  void establish(AuthData auth, {bool rememberMe = true}) {
    _rememberOnConfirm = rememberMe;
    restoring = false;
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
    unawaited(_rememberOnConfirm
        ? store.writeSession(StoredSession(_token!, expiresAt!)) : store.clearSession());
    notifyListeners();
  }

  Future<void> restore({
    required Future<UserDto> Function() fetchMe,
    Future<void> Function()? loadZone,
  }) async {
    if (restoring || isValid) return;
    final expected = ++generation;
    restoring = true;
    notifyListeners();
    try {
      final stored = await store.readSession();
      if (generation != expected || stored == null) return;
      if (!_now().isBefore(stored.expiresAt)) {
        await store.clearSession();
        return;
      }
      _rememberOnConfirm = true;
      _token = stored.accessToken;
      expiresAt = stored.expiresAt;
      verified = false;
      _expiryTimer?.cancel();
      _expiryTimer = Timer(stored.expiresAt.difference(_now()), () => clear(expired: true));
      final me = await fetchMe();
      if (generation != expected) return;
      if (!isValid) {
        clear(expired: true);
        return;
      }
      user = me;
      verified = true;
      if (me.hasZone && loadZone != null) await loadZone();
    } catch (_) {
      if (generation == expected) clear();
    } finally {
      if (generation == expected) {
        restoring = false;
        notifyListeners();
      }
    }
  }

  void checkExpiry() {
    if (_token != null && !isValid) clear(expired: true);
  }

  bool markZoneSaved(int expectedGeneration) {
    if (generation != expectedGeneration || !isValid || !verified || user == null) {
      return false;
    }
    user = UserDto.fromJson({...user!.toJson(), 'has_zone': true});
    notifyListeners();
    return true;
  }

  void clear({bool expired = false}) {
    generation++;
    restoring = false;
    unawaited(store.clearSession());
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
    generation++;
    _expiryTimer?.cancel();
    super.dispose();
  }
}
