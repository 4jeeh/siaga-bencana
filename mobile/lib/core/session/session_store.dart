import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class StoredSession {
  const StoredSession(this.accessToken, this.expiresAt);
  final String accessToken;
  final DateTime expiresAt;
}

abstract interface class SessionStore {
  Future<StoredSession?> readSession();
  Future<void> writeSession(StoredSession session);
  Future<void> clearSession();
  Future<bool> hasPromptedOnboarding();
  Future<void> markOnboardingPrompted();
}

class MemorySessionStore implements SessionStore {
  MemorySessionStore({StoredSession? initialSession, bool onboardingPrompted = true})
      : _session = initialSession, _prompted = onboardingPrompted;
  StoredSession? _session;
  bool _prompted;

  @override
  Future<StoredSession?> readSession() async => _session;
  @override
  Future<void> writeSession(StoredSession session) async { _session = session; }
  @override
  Future<void> clearSession() async { _session = null; }
  @override
  Future<bool> hasPromptedOnboarding() async => _prompted;
  @override
  Future<void> markOnboardingPrompted() async { _prompted = true; }
}

class SecureSessionStore implements SessionStore {
  SecureSessionStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();
  final FlutterSecureStorage _storage;
  static const _sessionKey = 'siaga_session_v1';
  static const _onboardingKey = 'siaga_onboarding_prompted_v1';
  bool _prompted = false;
  Future<void> _pending = Future.value();

  // Serialize writes and deletes so logout wins over an earlier login write.
  Future<void> _update(Future<void> Function() action) {
    return _pending = _pending.then((_) async {
      try {
        await action();
      } on FormatException {
        return;
      } on PlatformException {
        return;
      } on MissingPluginException {
        return;
      }
    });
  }

  @override
  Future<StoredSession?> readSession() async {
    await _pending;
    try {
      final raw = await _storage.read(key: _sessionKey);
      if (raw == null) return null;
      final value = jsonDecode(raw);
      if (value case {'access_token': String token, 'expires_at': String expiry}
          when token.trim().isNotEmpty) {
        return StoredSession(token, DateTime.parse(expiry).toUtc());
      }
      throw const FormatException('Sesi tidak valid.');
    } on FormatException {
      await clearSession();
      return null;
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  @override
  Future<void> writeSession(StoredSession session) => _update(() =>
      _storage.write(key: _sessionKey, value: jsonEncode({
        'access_token': session.accessToken,
        'expires_at': session.expiresAt.toUtc().toIso8601String(),
      })));

  @override
  Future<void> clearSession() => _update(() => _storage.delete(key: _sessionKey));

  @override
  Future<bool> hasPromptedOnboarding() async {
    if (_prompted) return true;
    try {
      return await _storage.read(key: _onboardingKey) == 'true';
    } on FormatException {
      return _prompted;
    } on PlatformException {
      return _prompted;
    } on MissingPluginException {
      return _prompted;
    }
  }

  @override
  Future<void> markOnboardingPrompted() {
    _prompted = true;
    return _update(() => _storage.write(key: _onboardingKey, value: 'true'));
  }
}
