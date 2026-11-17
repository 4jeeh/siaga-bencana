import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/session/session_coordinator.dart';
import 'zone_dto.dart';
import 'zone_view_model.dart';

class ZoneForm extends StatelessWidget {
  const ZoneForm({super.key, this.editZone = false});
  final bool editZone;

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ZoneViewModel>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('UI-01c \u2022 Atur Zona Pantau', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 16),
        const Text('Satu titik pantau, tidak mengikuti GPS terus-menerus'),
        const SizedBox(height: 16),
        if (vm.loading) const LinearProgressIndicator(),
        if (vm.loading) const Text('Memuat zona pantau...'),
        OutlinedButton(
          onPressed: vm.busy ? null : vm.locateOnce,
          child: Text(vm.locating ? 'Mencari lokasi...' : 'Gunakan lokasi saya sekali'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: vm.busy ? null : () => context.push('/map?mode=pick_zone'),
          child: const Text('Pilih titik di peta / manual'),
        ),
        if (vm.gpsMessage != null) Semantics(
          liveRegion: true, child: Text(vm.gpsMessage!),
        ),
        if (vm.canOpenSettings) TextButton(
          onPressed: vm.openSettings, child: const Text('Buka Pengaturan'),
        ),
        const SizedBox(height: 16),
        Card(child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(validCoordinates(vm.latitude, vm.longitude)
              ? 'Lintang: ${vm.latitude}\nBujur: ${vm.longitude}'
              : 'Pilih koordinat melalui GPS sekali atau peta / manual.'),
        )),
        const SizedBox(height: 16),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final radius in [25, 50, 100]) ChoiceChip(
            label: Text('$radius km'), selected: vm.radiusKm == radius,
            onSelected: vm.busy ? null : (_) => vm.updatePreferences(radius: radius),
          ),
        ]),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Gempa & Potensi Tsunami'),
          value: vm.notifyEarthquake,
          onChanged: vm.busy ? null : (value) => vm.updatePreferences(earthquake: value),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Cuaca Ekstrem'), value: vm.notifyWeather,
          onChanged: vm.busy ? null : (value) => vm.updatePreferences(weather: value),
        ),
        const Text('Toggle hanya memengaruhi notifikasi baru'),
        const SizedBox(height: 16),
        if (vm.error != null) ...[
          Semantics(liveRegion: true, child: Text(vm.error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error))),
          if (!vm.hasLoaded)
            TextButton(onPressed: vm.busy ? null : vm.load, child: const Text('Coba Lagi'))
          else
            const Text('Periksa isian lalu tekan Simpan Zona Pantau untuk mencoba lagi.'),
        ],
        if (!validCoordinates(vm.latitude, vm.longitude))
          const Text('Simpan belum tersedia: pilih koordinat yang valid terlebih dahulu.'),
        FilledButton(
          key: const Key('save-zone'),
          onPressed: !vm.canSave ? null : () async {
            final router = GoRouter.of(context);
            final session = context.read<SessionCoordinator>();
            final generation = session.generation;
            final target = editZone ? '/profile' : session.pendingDestination ?? '/home';
            if (await vm.save() && session.generation == generation && session.canNavigate) {
              session.pendingDestination = null;
              router.go(target);
            }
          },
          child: Text(vm.saving ? 'Menyimpan...' : 'Simpan Zona Pantau'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: editZone && vm.busy ? null : () {
            if (editZone) {
              vm.resetDraft();
              context.go('/profile');
            } else {
              context.read<SessionCoordinator>().clear();
            }
          },
          child: Text(editZone ? 'Kembali' : 'Keluar'),
        ),
      ],
    );
  }
}
