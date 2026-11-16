import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/routing/placeholder_page.dart';

class EventDetailScreen extends StatelessWidget {
  const EventDetailScreen({super.key, required this.eventId});
  final String eventId;
  @override
  Widget build(BuildContext context) => PlaceholderPage(
    title: 'Detail Bencana',
    icon: Icons.info_outline,
    child: OutlinedButton.icon(
      onPressed: () => context.canPop() ? context.pop() : context.go('/home'),
      icon: const Icon(Icons.arrow_back),
      label: const Text('Kembali'),
    ),
  );
}
