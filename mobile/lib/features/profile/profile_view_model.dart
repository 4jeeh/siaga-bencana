import 'package:flutter/foundation.dart';

import '../../core/session/session_coordinator.dart';
import '../auth/auth_repository.dart';
import '../notifications/local_notification_service.dart';
import '../notifications/notification_view_model.dart';
import '../zone/zone_view_model.dart';

class ProfileViewModel extends ChangeNotifier {
  ProfileViewModel(this.auth, this.zone, this.history, this.local, this.session);
  final AuthRepository auth;
  final ZoneViewModel zone;
  final NotificationViewModel history;
  final LocalNotificationService local;
  final SessionCoordinator session;
  bool _disposed = false;
  int _permissionRequest = 0;
  NotificationPermissionState permissionState = NotificationPermissionState.unknown;
  String? permissionNotice, accountError;
  int? _accountErrorGeneration;
  String? get currentAccountError => _accountErrorGeneration == session.generation ? accountError : null;

  Future<void> refreshProfile() async {
    if (!session.canNavigate) return;
    await Future.wait([_refreshAccount(), zone.load(), history.refresh(), checkPermission()]);
  }

  Future<void> _refreshAccount() async {
    final generation = session.generation;
    try {
      final user = await auth.me();
      if (_disposed || generation != session.generation) return;
      accountError = null;
      session.confirm(user, generation);
    } catch (_) {
      if (_disposed || generation != session.generation) return;
      _accountErrorGeneration = generation;
      accountError = 'Profil gagal diperbarui.';
    }
    notifyListeners();
  }

  Future<void> checkPermission() => _permission(local.checkPermission);
  Future<void> requestOsPermission() => _permission(local.requestPermission);
  Future<void> _permission(Future<NotificationPermissionState> Function() action) async {
    final request = ++_permissionRequest;
    try {
      final state = await action();
      if (_disposed || request != _permissionRequest) return;
      permissionState = state;
      permissionNotice = null;
    } catch (_) {
      if (_disposed || request != _permissionRequest) return;
      permissionNotice = 'Izin notifikasi tidak dapat diperiksa.';
    }
    notifyListeners();
  }

  Future<void> openOsNotificationSettings() async {
    try {
      if (await local.openOsSettings()) return;
    } catch (_) {
      // Some devices do not expose notification settings.
    }
    if (_disposed) return;
    permissionNotice = 'Pengaturan notifikasi tidak dapat dibuka.';
    notifyListeners();
  }
  void logout() => session.clear();
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
