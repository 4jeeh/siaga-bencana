import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../features/auth/auth_view_model.dart';
import '../theme/app_theme.dart';

class PlaceholderPage extends StatelessWidget {
  const PlaceholderPage({
    super.key,
    required this.title,
    required this.icon,
    this.child,
  });
  final String title;
  final IconData icon;
  final Widget? child;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          if (context.watch<AuthViewModel>().healthMeta?.isSimulated ==
              true) ...[
            const Text(
              'SIMULASI — data demo',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.simulation),
            ),
            const SizedBox(height: 24),
          ],
          Icon(icon, size: 56, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 24),
          const Text(
            'Dalam pengembangan Slice berikutnya',
            textAlign: TextAlign.center,
          ),
          if (child != null) ...[const SizedBox(height: 24), child!],
        ],
      ),
    ),
  );
}
