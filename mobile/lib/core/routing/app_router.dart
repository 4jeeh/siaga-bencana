import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/account_screen.dart';
import '../../features/home/home_screen.dart';
import '../../features/map/map_screen.dart';
import '../../features/reports/reports_screen.dart';
import '../../features/profile/profile_screen.dart';
import '../../features/event_detail/event_detail_screen.dart';
import '../session/session_coordinator.dart';

const mainRoutes = [
  '/account',
  '/home',
  '/map',
  '/reports',
  '/profile',
  '/events/:eventId',
];

GoRouter createRouter(
  SessionCoordinator session, {
  String initialLocation = '/account',
}) => GoRouter(
  initialLocation: initialLocation,
  refreshListenable: session,
  redirect: (context, state) {
    final location = state.uri.path;
    if (!session.canNavigate) {
      if (location != '/account') {
        if (location.startsWith('/events/')) {
          session.pendingDestination = location;
        }
        return '/account';
      }
      return null;
    }
    if (location == '/account') {
      final target = session.pendingDestination ?? '/home';
      session.pendingDestination = null;
      return target;
    }
    return null;
  },
  routes: [
    GoRoute(path: '/account', builder: (_, _) => const AccountScreen()),
    ShellRoute(
      builder: (context, state, child) =>
          NavigationShell(location: state.uri.path, child: child),
      routes: [
        GoRoute(path: '/home', builder: (_, _) => const HomeScreen()),
        GoRoute(path: '/map', builder: (_, _) => const MapScreen()),
        GoRoute(path: '/reports', builder: (_, _) => const ReportsScreen()),
        GoRoute(path: '/profile', builder: (_, _) => const ProfileScreen()),
      ],
    ),
    GoRoute(
      path: '/events/:eventId',
      builder: (_, state) =>
          EventDetailScreen(eventId: state.pathParameters['eventId']!),
    ),
  ],
);

class NavigationShell extends StatelessWidget {
  const NavigationShell({
    super.key,
    required this.location,
    required this.child,
  });
  final String location;
  final Widget child;
  static const tabs = ['/home', '/map', '/reports', '/profile'];
  @override
  Widget build(BuildContext context) => Scaffold(
    body: child,
    bottomNavigationBar: NavigationBar(
      selectedIndex: tabs.indexOf(location).clamp(0, 3),
      onDestinationSelected: (index) => context.go(tabs[index]),
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.home_outlined),
          label: 'Beranda',
        ),
        NavigationDestination(icon: Icon(Icons.map_outlined), label: 'Peta'),
        NavigationDestination(
          icon: Icon(Icons.campaign_outlined),
          label: 'Lapor',
        ),
        NavigationDestination(
          icon: Icon(Icons.person_outline),
          label: 'Profil',
        ),
      ],
    ),
  );
}
