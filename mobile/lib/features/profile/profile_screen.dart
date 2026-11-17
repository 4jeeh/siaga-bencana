import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/session/session_coordinator.dart';
import '../zone/zone_view_model.dart';
import '../auth/auth_view_model.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionCoordinator>();
    final vm = context.watch<ZoneViewModel>();
    final simulated = context.watch<AuthViewModel>().healthMeta?.isSimulated == true;
    final zone = vm.savedZone;
    return Scaffold(
      appBar: AppBar(title: const Text('Profil')),
      body: SafeArea(child: Center(child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (simulated) const Text('SIMULASI - data demo'),
            Text(session.user?.displayName ?? '', style: Theme.of(context).textTheme.headlineSmall),
            Text(session.user?.email ?? ''),
            Text('Peran: ${session.user?.role ?? ""}'),
            const SizedBox(height: 24),
            Text('Zona pantau tersimpan', style: Theme.of(context).textTheme.titleLarge),
            if (vm.loading) const LinearProgressIndicator(),
            if (zone != null) ...[
              Text('Lintang: ${zone.latitude}\nBujur: ${zone.longitude}'),
              Text('Radius: ${zone.radiusKm} km'),
              Text('Gempa & Potensi Tsunami: ${zone.notifyEarthquake ? "Aktif" : "Nonaktif"}'),
              Text('Cuaca Ekstrem: ${zone.notifyWeather ? "Aktif" : "Nonaktif"}'),
            ] else if (!vm.loading) const Text('Zona belum tersedia.'),
            if (vm.error != null) ...[
              Text(vm.error!),
              TextButton(onPressed: vm.load, child: const Text('Coba Lagi')),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: vm.busy ? null : () {
                vm.resetDraft();
                context.go('/account?edit=zone');
              },
              child: const Text('Ubah Zona Pantau'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(onPressed: session.clear, child: const Text('Keluar')),
          ]),
        ),
      ))),
    );
  }
}
