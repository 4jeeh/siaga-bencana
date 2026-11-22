import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';

import 'notification_dto.dart';

enum NotificationPermissionState { unknown, granted, denied }

const summaryNotificationId = 1;

int stableLocalNotificationId(String key) {
  var hash = 0x811c9dc5;
  for (final unit in key.codeUnits) {
    hash ^= unit;
    // Shift/add for identical low bits on native and JavaScript targets.
    hash = (hash + (hash << 1) + (hash << 4) + (hash << 7) +
        (hash << 8) + (hash << 24)) & 0x7fffffff;
  }
  return hash <= summaryNotificationId ? hash + 2 : hash;
}

String localAlertTitle(String title, bool simulated) =>
    simulated ? '[SIMULASI] $title' : title;

abstract interface class LocalNotificationService {
  Future<void> initialize({required void Function(String eventId) onTapEvent});
  Future<NotificationPermissionState> checkPermission();
  Future<NotificationPermissionState> requestPermission();
  Future<bool> openOsSettings();
  Future<void> showAlert(NotificationDto alert);
  Future<void> showSummary({required int count, required String latestTitle,
    required bool isSimulated, String? eventId});
  Future<void> cancelAll();
}

class NoopLocalNotificationService implements LocalNotificationService {
  const NoopLocalNotificationService();
  @override
  Future<void> initialize({required void Function(String) onTapEvent}) async {}
  @override
  Future<NotificationPermissionState> checkPermission() async => NotificationPermissionState.unknown;
  @override
  Future<NotificationPermissionState> requestPermission() => checkPermission();
  @override
  Future<bool> openOsSettings() async => false;
  @override
  Future<void> showAlert(NotificationDto alert) async {}
  @override
  Future<void> showSummary({required int count, required String latestTitle,
    required bool isSimulated, String? eventId}) async {}
  @override
  Future<void> cancelAll() async {}
}

class FlutterLocalNotificationService implements LocalNotificationService {
  final _plugin = FlutterLocalNotificationsPlugin();
  final _owners = <int, String>{};
  Future<void>? _initialization;
  bool _requested = false;
  int _generation = 0;
  bool get _supported => !kIsWeb && (defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS);
  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
  IOSFlutterLocalNotificationsPlugin? get _ios =>
      _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();

  @override
  Future<void> initialize({required void Function(String) onTapEvent}) =>
      _initialization = _initialize(onTapEvent);

  Future<void> _initialize(void Function(String) onTapEvent) async {
    if (!_supported) return;
    const darwin = DarwinInitializationSettings(requestAlertPermission: false,
      requestBadgePermission: false, requestSoundPermission: false);
    await _plugin.initialize(settings: const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'), iOS: darwin, macOS: darwin),
      onDidReceiveNotificationResponse: (response) {
        final id = response.payload;
        if (id != null && id.isNotEmpty) onTapEvent(id);
      });
    final launch = await _plugin.getNotificationAppLaunchDetails();
    final id = launch?.notificationResponse?.payload;
    if (launch?.didNotificationLaunchApp == true && id != null && id.isNotEmpty) onTapEvent(id);
  }

  @override
  Future<NotificationPermissionState> checkPermission() async {
    if (!_supported) return NotificationPermissionState.unknown;
    final enabled = defaultTargetPlatform == TargetPlatform.android
        ? await _android?.areNotificationsEnabled() : (await _ios?.checkPermissions())?.isEnabled;
    if (enabled == true) return NotificationPermissionState.granted;
    return _requested ? NotificationPermissionState.denied : NotificationPermissionState.unknown;
  }

  @override
  Future<NotificationPermissionState> requestPermission() async {
    if (!_supported) return NotificationPermissionState.unknown;
    _requested = true;
    final allowed = defaultTargetPlatform == TargetPlatform.android
        ? await _android?.requestNotificationsPermission()
        : await _ios?.requestPermissions(alert: true, badge: true, sound: true);
    return allowed == true ? NotificationPermissionState.granted : NotificationPermissionState.denied;
  }

  @override
  Future<bool> openOsSettings() async {
    if (!_supported) return false;
    try {
      if (await _plugin.openAppNotificationSettings() == true) return true;
    } on PlatformException {
      // Fall back to the app settings when the notification panel is unavailable.
    }
    return Geolocator.openAppSettings();
  }

  @override
  Future<void> showAlert(NotificationDto alert) async {
    if (!alert.presentAsActiveAlert || !_supported) return;
    var id = stableLocalNotificationId(alert.id);
    while (_owners.containsKey(id) && _owners[id] != alert.id) {
      id = id == 0x7fffffff ? 2 : id + 1;
    }
    _owners[id] = alert.id;
    await _show(id, localAlertTitle(alert.title, alert.isSimulated),
        'Peringatan resmi BMKG di zona pantau Anda.', alert.eventId);
  }

  @override
  Future<void> showSummary({required int count, required String latestTitle,
    required bool isSimulated, String? eventId}) =>
      _show(summaryNotificationId, localAlertTitle('$count peringatan baru', isSimulated),
        latestTitle, eventId);

  Future<void> _show(int id, String title, String body, String? eventId) async {
    final generation = _generation;
    await _initialization;
    if (generation != _generation) return;
    if (await checkPermission() != NotificationPermissionState.granted || generation != _generation) return;
    const android = AndroidNotificationDetails('siaga_bencana_alerts',
      'Peringatan Siaga Bencana', channelDescription: 'Peringatan resmi BMKG pada zona pantau aktif Anda',
      importance: Importance.max, priority: Priority.high);
    await _plugin.show(id: id, title: title, body: body, payload: eventId,
      notificationDetails: const NotificationDetails(android: android, iOS: DarwinNotificationDetails()));
  }

  @override
  Future<void> cancelAll() async {
    _generation++;
    _owners.clear();
    if (_supported) await _plugin.cancelAll();
  }
}
