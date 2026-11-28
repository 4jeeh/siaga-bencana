import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/session/session_coordinator.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/labels.dart';
import '../../core/utils/time_format.dart';
import '../../core/widgets/permission_onboarding_dialog.dart';
import '../../core/widgets/status_banners.dart';
import '../../core/widgets/ui_kit.dart';
import '../auth/auth_view_model.dart';
import '../events/event_dto.dart';
import '../events/event_feed_view_model.dart';
import '../profile/profile_view_model.dart';
import '../weather/weather_dto.dart';
import '../weather/weather_view_model.dart';
import '../zone/location_service.dart';
import '../zone/zone_dto.dart';
import '../zone/zone_view_model.dart';

void _editZone(BuildContext context) {
  context.read<ZoneViewModel>().resetDraft();
  context.go('/account?edit=zone');
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _promptPermissions());
  }

  Future<void> _promptPermissions() async {
    if (!mounted) return;
    final session = context.read<SessionCoordinator>();
    final generation = session.generation;
    if (!session.canNavigate || await session.store.hasPromptedOnboarding()) {
      return;
    }
    if (!mounted ||
        generation != session.generation ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    final allowed = await showDialog<bool>(
      context: context,
      builder: (_) => const PermissionOnboardingDialog(),
    );
    await session.store.markOnboardingPrompted();
    if (!mounted || allowed != true || generation != session.generation) return;
    await context.read<ProfileViewModel>().requestOsPermission();
    if (!mounted || generation != session.generation) return;
    if (context.read<ZoneViewModel>().locationService
        case LocationPermissionRequester requester) {
      await requester.requestLocationPermission();
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<EventFeedViewModel>();
    final simulation =
        context.watch<AuthViewModel>().healthMeta?.isSimulated == true ||
        vm.meta?.isSimulated == true;
    final status = switch (vm) {
      EventFeedViewModel(initialLoading: true) => 'Memuat feed',
      EventFeedViewModel(refreshing: true) => 'Memperbarui feed',
      EventFeedViewModel(loadingMore: true) => 'Memuat informasi berikutnya',
      EventFeedViewModel(zoneRequired: true) => 'Zona pantau belum aktif.',
      _ =>
        vm.error ?? vm.loadMoreError ?? '${vm.items.length} informasi dimuat',
    };
    return Scaffold(
      appBar: AppBar(title: const Text('Beranda')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              children: [
                if (simulation) const SimulationBanner(),
                Semantics(
                  container: true,
                  liveRegion: true,
                  label: status,
                  child: const SizedBox.shrink(),
                ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: () async {
                      await Future.wait([
                        vm.refresh(),
                        context.read<WeatherViewModel>().refresh(),
                      ]);
                    },
                    child: ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(AppSpace.m),
                      itemCount: vm.items.length + 2,
                      itemBuilder: (context, index) {
                        if (index == 0) return _FeedHeader(vm);
                        if (index > vm.items.length) return _FeedFooter(vm);
                        final item = vm.items[index - 1];
                        return _EventCard(key: ValueKey(item.id), item: item);
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FeedHeader extends StatelessWidget {
  const _FeedHeader(this.vm);
  final EventFeedViewModel vm;

  @override
  Widget build(BuildContext context) {
    final zoneVm = context.watch<ZoneViewModel>();
    final zone = zoneVm.savedZone;
    final weather = context.watch<WeatherViewModel>().weather;
    final sources = vm.meta?.sources;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (sources != null) ...[
          FreshnessBanner(sources: sources),
          const SizedBox(height: AppSpace.s),
        ],
        _ZoneHeroCard(
          zone: zone,
          locationLabel: zoneVm.selectedLocationLabel,
          weather: weather,
        ),
        const SizedBox(height: AppSpace.m),
        IconLabel(
          icon: Icons.info_outline,
          text:
              'Prioritas informasi aplikasi, bukan penilaian risiko ilmiah. Di luar radius bukan berarti aman.',
          color: AppColors.textMuted,
          style: Theme.of(context).textTheme.bodySmall,
          iconSize: 16,
        ),
        const SizedBox(height: AppSpace.l),
        const SectionHeader('Kejadian terbaru'),
        const SizedBox(height: AppSpace.s),
        LayoutBuilder(
          builder: (context, constraints) => Wrap(
            children: [
              SegmentedButton<bool>(
                direction:
                    constraints.maxWidth <
                        MediaQuery.textScalerOf(context).scale(150)
                    ? Axis.vertical
                    : Axis.horizontal,
                style: SegmentedButton.styleFrom(
                  minimumSize: const Size(48, 48),
                ),
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: true, label: Text('Sekitar')),
                  ButtonSegment(value: false, label: Text('Semua')),
                ],
                selected: {vm.radiusOnly},
                onSelectionChanged: (values) => vm.setFilters(
                  category: vm.category,
                  radiusOnly: values.single,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.s),
        Wrap(
          spacing: AppSpace.s,
          runSpacing: AppSpace.s,
          children: [
            for (final entry in const <String?, String>{
              null: 'Semua jenis',
              'earthquake': 'Gempa',
              'extreme_weather': 'Cuaca Ekstrem',
            }.entries)
              FilterChip(
                label: Text(entry.value),
                selected: vm.category == entry.key,
                materialTapTargetSize: MaterialTapTargetSize.padded,
                onSelected: (_) => vm.setFilters(
                  category: entry.key,
                  radiusOnly: vm.radiusOnly,
                ),
              ),
          ],
        ),
        if (vm.category == 'earthquake') ...[
          const SizedBox(height: AppSpace.s),
          Wrap(
            spacing: AppSpace.s,
            runSpacing: AppSpace.s,
            children: [
              for (final entry in const {
                'recent': 'Terbaru',
                'priority': 'Prioritas',
              }.entries)
                ChoiceChip(
                  label: Text(entry.value),
                  selected: vm.sort == entry.key,
                  onSelected: (_) => vm.setFilters(
                    category: vm.category,
                    radiusOnly: vm.radiusOnly,
                    sort: entry.key,
                  ),
                ),
            ],
          ),
        ],
        if (!vm.radiusOnly && vm.category != 'earthquake') ...[
          const SizedBox(height: AppSpace.s),
          Wrap(
            spacing: AppSpace.s,
            runSpacing: AppSpace.s,
            children: [
              for (final entry in const {
                'active': 'Aktif',
                'all': 'Semua status',
              }.entries)
                ChoiceChip(
                  label: Text(entry.value),
                  selected: vm.weatherStatus == entry.key,
                  onSelected: (_) => vm.setFilters(
                    category: vm.category,
                    radiusOnly: false,
                    weatherStatus: entry.key,
                  ),
                ),
            ],
          ),
        ],
        if (vm.refreshing)
          const Padding(
            padding: EdgeInsets.only(top: AppSpace.s),
            child: LinearProgressIndicator(),
          ),
        if (vm.error != null) ...[
          const SizedBox(height: AppSpace.s),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpace.m),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(vm.error!),
                  if (vm.lastLoadedAt != null)
                    Text(
                      'Data terakhir dimuat ${formatLocalDateTime(vm.lastLoadedAt!)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  const SizedBox(height: AppSpace.s),
                  OutlinedButton(
                    onPressed: vm.refresh,
                    child: const Text('Coba Lagi'),
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: AppSpace.s),
      ],
    );
  }
}

class _ZoneHeroCard extends StatelessWidget {
  const _ZoneHeroCard({
    required this.zone,
    required this.locationLabel,
    required this.weather,
  });

  final ZoneDto? zone;
  final String? locationLabel;
  final CurrentWeatherDto? weather;

  IconData _weatherIcon(String code) => switch (code) {
    'clear' => Icons.wb_sunny_outlined,
    'partly_cloudy' => Icons.wb_cloudy_outlined,
    'cloudy' => Icons.cloud_outlined,
    'fog' => Icons.foggy,
    'drizzle' || 'rain' => Icons.grain,
    'heavy_rain' => Icons.water_drop_outlined,
    'thunderstorm' => Icons.thunderstorm_outlined,
    _ => Icons.cloud_queue,
  };

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final subWhite = Colors.white.withValues(alpha: 0.85);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const IconLabel(
              icon: Icons.radar,
              text: 'Area Pantau Aktif',
              color: Colors.white,
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: AppSpace.s),
            if (zone != null) ...[
              Text(
                locationLabel ?? 'Titik pantau Anda',
                style: textTheme.titleLarge?.copyWith(color: Colors.white),
              ),
              const SizedBox(height: AppSpace.xs),
              Text(
                '${zone!.latitude.toStringAsFixed(4)}, ${zone!.longitude.toStringAsFixed(4)}',
                style: textTheme.bodySmall?.copyWith(
                  color: subWhite,
                  fontFeatures: tabularFigures,
                ),
              ),
              const SizedBox(height: AppSpace.m),
              Wrap(
                spacing: AppSpace.s,
                runSpacing: AppSpace.s,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  StatusPill(
                    icon: Icons.adjust,
                    label: 'Radius ${zone!.radiusKm} km',
                    foreground: Colors.white,
                    background: Colors.white.withValues(alpha: 0.16),
                    border: Colors.white.withValues(alpha: 0.24),
                  ),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: AppColors.primary,
                      minimumSize: const Size(48, 48),
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpace.l,
                        vertical: 10,
                      ),
                    ),
                    onPressed: () => _editZone(context),
                    icon: const Icon(Icons.edit_location_alt_outlined, size: 18),
                    label: const Text('Ubah'),
                  ),
                ],
              ),
            ] else ...[
              Text(
                'Area pantau belum diatur',
                style: textTheme.titleLarge?.copyWith(color: Colors.white),
              ),
              const SizedBox(height: AppSpace.m),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: AppColors.primary,
                    minimumSize: const Size(48, 48),
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpace.l,
                      vertical: 10,
                    ),
                  ),
                  onPressed: () => _editZone(context),
                  icon: const Icon(Icons.edit_location_alt_outlined, size: 18),
                  label: const Text('Atur'),
                ),
              ),
            ],
            if (weather != null) ...[
              Divider(color: Colors.white.withValues(alpha: 0.24), height: 24),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Semantics(
                    label:
                        'Cuaca saat ini: ${weather!.conditionLabel} · ${weather!.temperatureC.toStringAsFixed(0)}°C',
                    excludeSemantics: true,
                    child: Row(
                      children: [
                        ExcludeSemantics(
                          child: Icon(
                            _weatherIcon(weather!.conditionCode),
                            color: Colors.white,
                            size: 40,
                          ),
                        ),
                        const SizedBox(width: AppSpace.m),
                        Text(
                          '${weather!.temperatureC.toStringAsFixed(0)}°C',
                          style: textTheme.displaySmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontFeatures: tabularFigures,
                          ),
                        ),
                        const SizedBox(width: AppSpace.m),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                weather!.conditionLabel,
                                style: textTheme.titleMedium?.copyWith(
                                  color: Colors.white,
                                ),
                              ),
                              Text(
                                'Cuaca saat ini',
                                style: textTheme.bodySmall?.copyWith(
                                  color: subWhite,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpace.m),
                  MetricStrip(
                    tiles: [
                      MetricTile(
                        label: 'Kelembapan',
                        value: '${weather!.humidityPercent.toStringAsFixed(0)}%',
                        icon: Icons.water_drop_outlined,
                        dark: true,
                      ),
                      MetricTile(
                        label: 'Angin',
                        value: '${weather!.windSpeedKmh.toStringAsFixed(0)} km/j',
                        icon: Icons.air,
                        dark: true,
                      ),
                      MetricTile(
                        label: 'Hujan',
                        value: '${weather!.precipitationMm.toStringAsFixed(1)} mm',
                        icon: Icons.umbrella_outlined,
                        dark: true,
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpace.s),
                  Text(
                    'Cuaca: Open-Meteo',
                    style: textTheme.bodySmall?.copyWith(color: subWhite),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FeedFooter extends StatelessWidget {
  const _FeedFooter(this.vm);
  final EventFeedViewModel vm;
  @override
  Widget build(BuildContext context) {
    if (vm.initialLoading || vm.loadingMore) {
      return const Padding(
        padding: EdgeInsets.all(AppSpace.l),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (vm.zoneRequired) {
      return Column(
        children: [
          const Text('Zona pantau belum aktif.'),
          const SizedBox(height: AppSpace.s),
          OutlinedButton(
            onPressed: () => _editZone(context),
            child: const Text('Ubah Zona'),
          ),
        ],
      );
    }
    if (vm.items.isEmpty && vm.error == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpace.l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              vm.radiusOnly
                  ? 'Belum ada informasi yang cocok dengan radius ini.'
                  : 'Belum ada informasi yang cocok dengan filter ini.',
            ),
            if (vm.meta?.sources.any((source) => source.state == 'unavailable') ==
                true)
              const Text('Sebagian data sumber belum tersedia.'),
            const SizedBox(height: AppSpace.s),
            Wrap(
              spacing: AppSpace.s,
              runSpacing: AppSpace.s,
              children: [
                if (vm.radiusOnly)
                  OutlinedButton(
                    onPressed: () =>
                        vm.setFilters(category: vm.category, radiusOnly: false),
                    child: const Text('Semua'),
                  ),
                OutlinedButton(
                  onPressed: () => _editZone(context),
                  child: const Text('Ubah Zona'),
                ),
              ],
            ),
          ],
        ),
      );
    }
    if (vm.page?.hasMore == true) {
      return Column(
        children: [
          if (vm.loadMoreError != null) ...[
            Text(vm.loadMoreError!),
            if (vm.lastLoadedAt != null)
              Text(
                'Data terakhir dimuat ${formatLocalDateTime(vm.lastLoadedAt!)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
          const SizedBox(height: AppSpace.s),
          OutlinedButton(
            onPressed: vm.loadMore,
            child: Text(
              vm.loadMoreError == null ? 'Muat lagi' : 'Coba muat lagi',
            ),
          ),
        ],
      );
    }
    return const SizedBox.shrink();
  }
}

class _EventCard extends StatelessWidget {
  const _EventCard({super.key, required this.item});
  final EventSummaryDto item;

  Widget _time(BuildContext context, DateTime value) => Tooltip(
    message: formatFullTooltipDateTime(value),
    child: IconLabel(
      icon: Icons.schedule,
      text: formatLocalDateTime(value),
      color: AppColors.textMuted,
      style: Theme.of(context).textTheme.bodySmall,
      iconSize: 16,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final quake = item.source == 'BMKG_TEWS';
    final p = item.priority;
    final cap = item.cap;
    final distance = p.matchDistanceKm;
    final accent = quake
        ? switch (p.priorityLabel) {
            'high' => AppColors.error,
            'attention' => AppColors.warning,
            'ordinary' => AppColors.primary,
            _ => AppColors.outline,
          }
        : AppColors.warning;
    final priorityFg = accent == AppColors.outline
        ? AppColors.textMuted
        : accent;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: AccentCard(
        accent: accent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: AppSpace.s,
              runSpacing: AppSpace.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                IconLabel(
                  icon: quake ? Icons.sensors : Icons.thunderstorm_outlined,
                  text: quake ? 'BMKG — Gempa' : 'BMKG — Cuaca',
                  color: AppColors.textMuted,
                  style: textTheme.labelLarge?.copyWith(
                    color: AppColors.textMuted,
                  ),
                ),
                if (item.isSimulated) const SimulationBadge(),
              ],
            ),
            const SizedBox(height: AppSpace.s),
            Text(
              item.title,
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpace.s),
            if (quake) ...[
              StatusPill(
                icon: Icons.flag_outlined,
                label: p.priorityDisplay == null
                    ? 'Prioritas belum tersedia'
                    : 'Prioritas ${p.priorityDisplay} — ${priorityLevelLabels[p.priorityLabel]}',
                foreground: priorityFg,
                background: priorityFg.withValues(alpha: 0.10),
                textColor: priorityFg == AppColors.warning
                    ? AppColors.textPrimary
                    : null,
              ),
              const SizedBox(height: AppSpace.s),
              Wrap(
                spacing: AppSpace.l,
                runSpacing: AppSpace.xs,
                children: [
                  _time(context, item.occurredAt),
                  if (distance != null)
                    IconLabel(
                      icon: Icons.place_outlined,
                      text: formatDistanceKm(distance),
                      color: AppColors.textMuted,
                      style: textTheme.bodySmall,
                      iconSize: 16,
                    ),
                ],
              ),
            ] else ...[
              _time(context, item.occurredAt),
              if (cap != null && cap.areaDescriptions.isNotEmpty) ...[
                const SizedBox(height: AppSpace.s),
                Text(
                  cap.areaDescriptions.join(', '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodyMedium,
                ),
              ],
              const SizedBox(height: AppSpace.s),
              Wrap(
                spacing: AppSpace.s,
                runSpacing: AppSpace.s,
                children: [
                  StatusPill(
                    icon: Icons.warning_amber,
                    label:
                        'Keparahan: ${capSeverityLabel(cap?.severity) ?? 'Belum tersedia'}',
                    foreground: AppColors.warning,
                    background: AppColors.warning.withValues(alpha: 0.10),
                    textColor: AppColors.textPrimary,
                  ),
                  StatusPill(
                    icon: item.lifecycleStatus == 'active'
                        ? Icons.notifications_active_outlined
                        : Icons.info_outline,
                    label: lifecycleLabels[item.lifecycleStatus]!,
                    foreground: AppColors.textPrimary,
                    background: AppColors.surfaceVariant,
                  ),
                ],
              ),
              if (cap != null) ...[
                const SizedBox(height: AppSpace.s),
                Text(
                  'Berlaku mulai ${formatLocalDateTime(cap.effective)}',
                  style: textTheme.bodySmall,
                ),
                Text(
                  cap.expires == null
                      ? 'Akhir masa berlaku belum tersedia'
                      : 'Hingga ${formatLocalDateTime(cap.expires!)}',
                  style: textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: AppSpace.s),
              IconLabel(
                icon: Icons.place_outlined,
                text: switch (p.matchMethod) {
                  'inside_polygon' => 'Di dalam area peringatan',
                  'near_polygon_sample' =>
                    'Perkiraan jarak centroid/vertex (bukan irisan eksak)',
                  'no_geometry' => 'Tanpa geometri poligon',
                  _ => 'Jarak ke titik kejadian',
                },
                color: AppColors.textMuted,
                style: textTheme.bodySmall,
                iconSize: 16,
              ),
              if (distance != null)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpace.xs),
                  child: Text(
                    formatDistanceKm(distance),
                    style: textTheme.bodySmall,
                  ),
                ),
            ],
            const SizedBox(height: AppSpace.m),
            DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: ExpansionTile(
                key: PageStorageKey(item.id),
                leading: const Icon(Icons.help_outline, size: 20),
                title: const Text('Mengapa?'),
                expandedAlignment: Alignment.centerLeft,
                expandedCrossAxisAlignment: CrossAxisAlignment.start,
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                children: [
                  for (final reason in p.priorityReasons)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: IconLabel(
                        icon: Icons.chevron_right,
                        text: reason.text,
                        iconSize: 16,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpace.m),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonal(
                onPressed: () => context.push('/events/${item.id}'),
                child: const Text('Lihat Detail'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
