import 'dart:async';

import 'features/reports/moderation_view_model.dart';
import 'features/reports/report_repository.dart';
import 'features/reports/report_photo_service.dart';
import 'features/reports/reports_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import 'core/network/api_client.dart';
import 'core/routing/app_router.dart';
import 'core/session/session_coordinator.dart';
import 'core/theme/app_theme.dart';
import 'core/session/session_store.dart';
import 'features/weather/weather_repository.dart';
import 'features/weather/weather_view_model.dart';
import 'features/auth/auth_repository.dart';
import 'features/auth/auth_view_model.dart';
import 'features/event_detail/event_detail_view_model.dart';
import 'features/events/event_feed_view_model.dart';
import 'features/events/event_repository.dart';
import 'features/map/map_repository.dart';
import 'features/map/map_view_model.dart';
import 'features/notifications/local_notification_service.dart';
import 'features/notifications/notification_coordinator.dart';
import 'features/notifications/notification_repository.dart';
import 'features/notifications/notification_view_model.dart';
import 'features/profile/profile_view_model.dart';
import 'features/zone/location_service.dart';
import 'features/zone/zone_repository.dart';
import 'features/zone/zone_view_model.dart';

class SiagaApp extends StatefulWidget {
  const SiagaApp({
    super.key,
    required this.client,
    required this.baseUrl,
    this.session,
    this.sessionStore,
    this.initialLocation = '/account',
    this.textScaler,
    this.locationService,
    this.photoService,
    this.tileProvider,
    this.localNotificationService,
    this.notificationTiming,
    this.autoStartNotifications = true,
  });
  final http.Client client;
  final Uri baseUrl;
  final SessionCoordinator? session;
  final SessionStore? sessionStore;
  final String initialLocation;
  final TextScaler? textScaler;
  final LocationService? locationService;
  final ReportPhotoService? photoService;
  final TileProvider? tileProvider;
  final LocalNotificationService? localNotificationService;
  final NotificationTimingConfig? notificationTiming;
  final bool autoStartNotifications;
  @override
  State<SiagaApp> createState() => _SiagaAppState();
}

class _SiagaAppState extends State<SiagaApp> with WidgetsBindingObserver {
  late final SessionCoordinator session;
  late final ApiClient api;
  late final AuthViewModel auth;
  late final GoRouter router;
  late final ZoneViewModel zone;
  late final EventFeedViewModel feed;
  late final WeatherViewModel weather;
  late final MapViewModel map;
  late final EventDetailViewModel detail;
  late final NotificationViewModel notifications;
  late final NotificationCoordinator notificationCoordinator;
  late final ProfileViewModel profile;
  late final ReportsViewModel reports;
  late final ModerationViewModel moderation;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    session = widget.session ?? SessionCoordinator(store: widget.sessionStore);
    api = ApiClient(
      client: widget.client,
      baseUrl: widget.baseUrl,
      session: session,
    );
    zone = ZoneViewModel(
      ZoneRepository(api), session,
      widget.locationService ?? const GeolocatorLocationService(),
    );
    auth = AuthViewModel(AuthRepository(api), session);
    final events = EventRepository(api);
    feed = EventFeedViewModel(events, session, zone);
    weather = WeatherViewModel(WeatherRepository(api), session, zone);
    final repository = ReportRepository(api);
    reports = ReportsViewModel(repository, events, session, zone,
      widget.locationService ?? const GeolocatorLocationService(), widget.photoService ?? ImagePickerReportPhotoService());
    moderation = ModerationViewModel(repository, session, zone)..refreshReports = reports.refreshLists;
    detail = EventDetailViewModel(events, session, zone, repository);
    map = MapViewModel(MapRepository(api), session, zone);
    router = createRouter(
      session, initialLocation: widget.initialLocation,
      tileProvider: widget.tileProvider,
    );
    final local = widget.localNotificationService ?? (widget.autoStartNotifications
        ? FlutterLocalNotificationService() : const NoopLocalNotificationService());
    final notificationRepository = NotificationRepository(api);
    notifications = NotificationViewModel(notificationRepository, session);
    profile = ProfileViewModel(AuthRepository(api), zone, notifications, local, session);
    unawaited(_initializeNotifications(local));
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    notificationCoordinator = NotificationCoordinator(notificationRepository, notifications,
      session, local, enabled: widget.autoStartNotifications,
      resumed: lifecycle == null || lifecycle == AppLifecycleState.resumed,
      timing: widget.notificationTiming ?? const NotificationTimingConfig());
    if (session.canNavigate) feed.refresh();
    if (session.isValid && session.verified) zone.load();
    auth.checkHealth();
    if (widget.session == null && widget.sessionStore != null) unawaited(_restoreSession());
  }

  Future<void> _restoreSession() async {
    await session.restore(fetchMe: auth.repository.me, loadZone: zone.load);
    if (!mounted || !session.canNavigate) return;
    // The session listeners may already be refreshing for the restored zone.
    await Future.wait([
      if (!feed.initialLoading && !feed.refreshing) feed.refresh(),
      weather.refresh(),
    ]);
  }

  Future<void> _initializeNotifications(LocalNotificationService local) async {
    try {
      await local.initialize(onTapEvent: (eventId) {
        if (!mounted) return;
        final location = '/events/${Uri.encodeComponent(eventId)}';
        if (session.canNavigate) {
          router.push(location);
        } else {
          session.pendingDestination = location;
        }
      });
    } catch (_) {
      // The history and the network channel remain available without native alerts.
    }
    if (mounted) await profile.checkPermission();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    session.checkExpiry();
    notificationCoordinator.handleAppLifecycle(state);
    if (state == AppLifecycleState.resumed) unawaited(profile.checkPermission());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    notificationCoordinator.dispose();
    profile.dispose();
    notifications.dispose();
    router.dispose();
    auth.dispose();
    detail.dispose();
    moderation.dispose();
    reports.dispose();
    weather.dispose();
    feed.dispose();
    map.dispose();
    zone.dispose();
    api.close();
    if (widget.session == null) session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: session),
      ChangeNotifierProvider.value(value: auth),
      ChangeNotifierProvider.value(value: zone),
      ChangeNotifierProvider.value(value: profile),
      ChangeNotifierProvider.value(value: notifications),
      ChangeNotifierProvider.value(value: notificationCoordinator),
      ChangeNotifierProvider.value(value: feed),
      ChangeNotifierProvider.value(value: weather),
      ChangeNotifierProvider.value(value: detail),
      ChangeNotifierProvider.value(value: reports),
      ChangeNotifierProvider.value(value: moderation),
      ChangeNotifierProvider.value(value: map),
    ],
    child: MaterialApp.router(
      title: 'Siaga Bencana',
      debugShowCheckedModeBanner: false,
      theme: appTheme(),
      routerConfig: router,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: widget.textScaler ?? MediaQuery.textScalerOf(context),
        ),
        child: child!,
      ),
    ),
  );
}
