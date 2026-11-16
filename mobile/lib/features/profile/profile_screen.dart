import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/routing/placeholder_page.dart';
import '../../core/session/session_coordinator.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});
  @override
  Widget build(BuildContext context) => PlaceholderPage(
    title: 'Profil',
    icon: Icons.person_outline,
    child: OutlinedButton.icon(
      onPressed: () => context.read<SessionCoordinator>().clear(),
      icon: const Icon(Icons.logout),
      label: const Text('Keluar'),
    ),
  );
}
