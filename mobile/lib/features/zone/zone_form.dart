import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/session/session_coordinator.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/ui_kit.dart';
import '../notifications/notification_coordinator.dart';
import 'location_search_field.dart';
import 'zone_dto.dart';
import 'zone_view_model.dart';

class ZoneForm extends StatelessWidget {
  const ZoneForm({super.key, this.editZone = false});
  final bool editZone;

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ZoneViewModel>();
    final hasCoords = validCoordinates(vm.latitude, vm.longitude);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            'Atur Area Pantau',
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        const SizedBox(height: AppSpace.s),
        Text(
          'Pilih satu titik yang ingin Anda pantau. Titik ini tidak mengikuti GPS terus-menerus.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: AppColors.textMuted,
          ),
        ),
        const SizedBox(height: AppSpace.l),
        if (vm.loading) ...[
          const LinearProgressIndicator(),
          const SizedBox(height: AppSpace.xs),
          const Text('Memuat zona pantau...'),
          const SizedBox(height: AppSpace.m),
        ],
        LocationSearchField(onSelected: vm.applyLocationSuggestion),
        if (vm.selectedLocationLabel != null) ...[
          const SizedBox(height: AppSpace.m),
          IconLabel(
            icon: Icons.place,
            text: vm.selectedLocationLabel!,
            color: AppColors.primary,
          ),
        ],
        const SizedBox(height: AppSpace.m),
        LayoutBuilder(
          builder: (context, constraints) {
            final compactStyle = OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            );
            final gpsBtn = OutlinedButton.icon(
              style: compactStyle,
              onPressed: vm.busy ? null : vm.locateOnce,
              icon: const Icon(Icons.my_location),
              label: Text(
                vm.locating ? 'Mencari lokasi...' : 'Pakai GPS sekali',
              ),
            );
            final mapBtn = OutlinedButton.icon(
              style: compactStyle,
              onPressed: vm.busy
                  ? null
                  : () => context.push('/map?mode=pick_zone'),
              icon: const Icon(Icons.map_outlined),
              label: const Text('Pilih di peta'),
            );
            final sideBySide =
                constraints.maxWidth >= MediaQuery.textScalerOf(context).scale(300);
            if (sideBySide) {
              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: gpsBtn),
                    const SizedBox(width: AppSpace.s),
                    Expanded(child: mapBtn),
                  ],
                ),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                gpsBtn,
                const SizedBox(height: AppSpace.s),
                mapBtn,
              ],
            );
          },
        ),
        if (vm.gpsMessage != null) ...[
          const SizedBox(height: AppSpace.s),
          Semantics(liveRegion: true, child: Text(vm.gpsMessage!)),
        ],
        if (vm.canOpenSettings)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: vm.openSettings,
              child: const Text('Buka Pengaturan'),
            ),
          ),
        const SizedBox(height: AppSpace.m),
        DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: IconLabel(
              icon: Icons.pin_drop_outlined,
              text: hasCoords
                  ? 'Lintang: ${vm.latitude} · Bujur: ${vm.longitude}'
                  : 'Belum ada titik. Cari wilayah, pakai GPS, atau pilih di peta.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ),
        const SizedBox(height: AppSpace.l),
        const SectionHeader('Radius pantau'),
        const SizedBox(height: AppSpace.s),
        Wrap(
          spacing: AppSpace.s,
          runSpacing: AppSpace.s,
          children: [
            for (final radius in [25, 50, 100])
              ChoiceChip(
                label: Text('$radius km'),
                selected: vm.radiusKm == radius,
                onSelected: vm.busy
                    ? null
                    : (_) => vm.updatePreferences(radius: radius),
              ),
          ],
        ),
        const SizedBox(height: AppSpace.l),
        const SectionHeader('Notifikasi'),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(Icons.waves),
          title: const Text('Gempa & Potensi Tsunami'),
          value: vm.notifyEarthquake,
          onChanged: vm.busy
              ? null
              : (value) => vm.updatePreferences(earthquake: value),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(Icons.thunderstorm_outlined),
          title: const Text('Cuaca Ekstrem'),
          value: vm.notifyWeather,
          onChanged: vm.busy
              ? null
              : (value) => vm.updatePreferences(weather: value),
        ),
        Text(
          'Toggle hanya memengaruhi notifikasi baru',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: AppSpace.l),
        if (vm.error != null) ...[
          Semantics(
            liveRegion: true,
            child: Text(
              vm.error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
          if (!vm.hasLoaded)
            TextButton(
              onPressed: vm.busy ? null : vm.load,
              child: const Text('Coba Lagi'),
            )
          else
            const Text(
              'Periksa isian lalu tekan Simpan Zona Pantau untuk mencoba lagi.',
            ),
          const SizedBox(height: AppSpace.s),
        ],
        if (!hasCoords) ...[
          Text(
            'Simpan belum tersedia: pilih koordinat yang valid terlebih dahulu.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpace.s),
        ],
        FilledButton(
          key: const Key('save-zone'),
          onPressed: !vm.canSave
              ? null
              : () async {
                  final router = GoRouter.of(context);
                  final channel = context.read<NotificationCoordinator>();
                  final session = context.read<SessionCoordinator>();
                  final generation = session.generation;
                  final target = editZone
                      ? '/profile'
                      : session.pendingDestination ?? '/home';
                  if (await vm.save() &&
                      session.generation == generation &&
                      session.canNavigate) {
                    session.pendingDestination = null;
                    router.go(target);
                    if (editZone) await channel.zoneUpdated();
                  }
                },
          child: Text(vm.saving ? 'Menyimpan...' : 'Simpan Zona Pantau'),
        ),
        const SizedBox(height: AppSpace.s),
        OutlinedButton(
          onPressed: editZone && vm.busy
              ? null
              : () {
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
