import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/network/api_envelope.dart';
import '../../core/session/session_coordinator.dart';
import 'auth_dto.dart';
import 'auth_repository.dart';

class AuthViewModel extends ChangeNotifier {
  AuthViewModel(this.repository, this.session);
  final AuthRepository repository;
  final SessionCoordinator session;
  bool busy = false;
  bool checkingHealth = false;
  ApiMeta? healthMeta;
  String? healthError;
  ApiErrorEnvelope? error;
  int retrySeconds = 0;
  Timer? _retryTimer;
  bool _disposed = false;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> checkHealth() async {
    if (checkingHealth) return;
    checkingHealth = true;
    _notify();
    try {
      healthMeta = await repository.health();
      healthError = null;
    } catch (_) {
      healthMeta = null;
      healthError = 'API tidak terjangkau. Periksa koneksi dan alamat server.';
    } finally {
      checkingHealth = false;
      _notify();
    }
  }

  Future<void> submit({
    required String email,
    required String password,
    String? displayName,
    bool rememberMe = true,
  }) async {
    if (busy || retrySeconds > 0) return;
    busy = true;
    error = null;
    final initialGeneration = session.generation;
    int? establishedGeneration;
    _notify();
    try {
      final auth = displayName == null
          ? await repository.login(LoginRequest(email, password))
          : await repository.register(
              RegisterRequest(email, password, displayName),
            );
      if (_disposed || initialGeneration != session.generation) return;
      session.establish(auth, rememberMe: rememberMe);
      establishedGeneration = session.generation;
      final user = await repository.me();
      if (_disposed) return;
      session.confirm(user, establishedGeneration);
    } on ApiErrorEnvelope catch (failure) {
      error = failure;
      if (establishedGeneration == session.generation) session.clear();
      if (failure.statusCode == 429) {
        retrySeconds = (failure.retryAfter ?? 60).clamp(1, 3600);
        _retryTimer?.cancel();
        _retryTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
          retrySeconds--;
          if (retrySeconds <= 0) timer.cancel();
          _notify();
        });
      }
    } catch (_) {
      error = const ApiErrorEnvelope(
        code: 'INVALID_RESPONSE',
        message: 'Respons API tidak valid.',
      );
      if (establishedGeneration == session.generation) session.clear();
    } finally {
      busy = false;
      _notify();
    }
  }

  void clearError() {
    error = null;
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    _retryTimer?.cancel();
    super.dispose();
  }
}
