import 'package:flutter/material.dart';

import '../../core/routing/placeholder_page.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});
  @override
  Widget build(BuildContext context) =>
      const PlaceholderPage(title: 'Beranda', icon: Icons.home_outlined);
}
