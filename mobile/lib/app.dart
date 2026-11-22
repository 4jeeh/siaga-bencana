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
import 'features/auth/auth_repository.dart';
import 'features/auth/auth_view_model.dart';
import 'features/event_detail/event_detail_view_model.dart';
import 'features/events/event_feed_view_model.dart';
import 'features/events/event_repository.dart';
import 'features/map/map_repository.dart';
import 'features/map/map_view_model.dart';
import 'features/zone/location_service.dart';
import 'features/zone/zone_repository.dart';
import 'features/zone/zone_view_model.dart';

class SiagaApp extends StatefulWidget {
  const SiagaApp({
    super.key,
    required this.client,
    required this.baseUrl,
    this.session,
    this.initialLocation = '/account',
    this.textScaler,
    this.locationService,
    this.photoService,
    this.tileProvider,
  });
  final http.Client client;
  final Uri baseUrl;
  final SessionCoordinator? session;
  final String initialLocation;
  final TextScaler? textScaler;
  final LocationService? locationService;
  final ReportPhotoService? photoService;
  final TileProvider? tileProvider;
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
  late final MapViewModel map;
  late final EventDetailViewModel detail;
  late final ReportsViewModel reports;
  late final ModerationViewModel moderation;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    session = widget.session ?? SessionCoordinator();
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
    if (session.canNavigate) feed.refresh();
    if (session.isValid && session.verified) zone.load();
    auth.checkHealth();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) session.checkExpiry();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    router.dispose();
    auth.dispose();
    detail.dispose();
    moderation.dispose();
    reports.dispose();
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
      ChangeNotifierProvider.value(value: feed),
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
