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
    this.tileProvider,
  });
  final http.Client client;
  final Uri baseUrl;
  final SessionCoordinator? session;
  final String initialLocation;
  final TextScaler? textScaler;
  final LocationService? locationService;
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
    router = createRouter(
      session, initialLocation: widget.initialLocation,
      tileProvider: widget.tileProvider,
    );
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
