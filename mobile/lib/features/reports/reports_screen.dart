import 'package:flutter/material.dart';

import '../../core/routing/placeholder_page.dart';

class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key, this.eventId});
  final String? eventId;
  @override
  Widget build(BuildContext context) => PlaceholderPage(
    title: 'Lapor Warga',
    icon: Icons.campaign_outlined,
    child: eventId?.isNotEmpty == true ? Text('Terkait event: $eventId') : null,
  );
}
