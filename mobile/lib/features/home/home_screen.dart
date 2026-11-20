import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/utils/time_format.dart';
import '../../core/widgets/status_banners.dart';
import '../auth/auth_view_model.dart';
import '../events/event_dto.dart';
import '../events/event_feed_view_model.dart';
import '../zone/zone_view_model.dart';

void _editZone(BuildContext context) {
  context.read<ZoneViewModel>().resetDraft();
  context.go('/account?edit=zone');
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<EventFeedViewModel>();
    final simulation = context.watch<AuthViewModel>().healthMeta?.isSimulated == true ||
        vm.meta?.isSimulated == true;
    final status = switch (vm) {
      EventFeedViewModel(initialLoading: true) => 'Memuat feed',
      EventFeedViewModel(refreshing: true) => 'Memperbarui feed',
      EventFeedViewModel(loadingMore: true) => 'Memuat informasi berikutnya',
      EventFeedViewModel(zoneRequired: true) => 'Zona pantau belum aktif.',
      _ => vm.error ?? vm.loadMoreError ?? '${vm.items.length} informasi dimuat',
    };
    return Scaffold(
      appBar: AppBar(titleSpacing: 8, title: const Text('Beranda'), actions: [
        TextButton.icon(onPressed: () => _editZone(context),
          icon: const Icon(Icons.edit_location_alt_outlined), label: const Text('Ubah Zona')),
      ]),
      body: SafeArea(child: Center(child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Column(children: [
          if (simulation) const SimulationBanner(),
          Semantics(container: true, liveRegion: true, label: status, child: const SizedBox.shrink()),
          Expanded(child: RefreshIndicator(
            onRefresh: vm.refresh,
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(12),
              itemCount: vm.items.length + 2,
              itemBuilder: (context, index) {
                if (index == 0) return _FeedHeader(vm);
                if (index > vm.items.length) return _FeedFooter(vm);
                final item = vm.items[index - 1];
                return _EventCard(key: ValueKey(item.id), item: item);
              },
            ),
          )),
        ]),
      ))),
    );
  }
}

class _FeedHeader extends StatelessWidget {
  const _FeedHeader(this.vm);
  final EventFeedViewModel vm;

  @override
  Widget build(BuildContext context) {
    final zone = context.watch<ZoneViewModel>().savedZone;
    final sources = vm.meta?.sources;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (sources != null) FreshnessBanner(sources: sources),
      Card(child: Padding(padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Semantics(header: true,
            child: Text('Titik pantau', style: Theme.of(context).textTheme.titleMedium)),
          if (zone != null) Text('${zone.latitude}, ${zone.longitude} · Radius ${zone.radiusKm} km'),
          const SizedBox(height: 8),
          const Text('Prioritas informasi aplikasi, bukan penilaian risiko ilmiah. Di luar radius bukan berarti aman.'),
        ]),
      )),
      const SizedBox(height: 12),
      LayoutBuilder(builder: (context, constraints) => Wrap(children: [
        SegmentedButton<bool>(
          direction: constraints.maxWidth < MediaQuery.textScalerOf(context).scale(150)
              ? Axis.vertical : Axis.horizontal,
          style: SegmentedButton.styleFrom(minimumSize: const Size(48, 48)),
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: true, label: Text('Sekitar')),
            ButtonSegment(value: false, label: Text('Semua')),
          ],
          selected: {vm.radiusOnly},
          onSelectionChanged: (values) => vm.setFilters(category: vm.category, radiusOnly: values.single),
        ),
      ])),
      Wrap(spacing: 8, children: [
        for (final entry in const <String?, String>{null: 'Semua jenis', 'earthquake': 'Gempa',
          'extreme_weather': 'Cuaca Ekstrem'}.entries)
          FilterChip(label: Text(entry.value), selected: vm.category == entry.key,
            materialTapTargetSize: MaterialTapTargetSize.padded,
            onSelected: (_) => vm.setFilters(category: entry.key, radiusOnly: vm.radiusOnly)),
      ]),
      if (vm.category == 'earthquake')
        Wrap(spacing: 8, children: [
          for (final entry in const {'recent': 'Terbaru', 'priority': 'Prioritas'}.entries)
            ChoiceChip(label: Text(entry.value), selected: vm.sort == entry.key,
              onSelected: (_) => vm.setFilters(category: vm.category, radiusOnly: vm.radiusOnly, sort: entry.key)),
        ]),
      if (!vm.radiusOnly && vm.category != 'earthquake')
        Wrap(spacing: 8, children: [
          for (final entry in const {'active': 'Aktif', 'all': 'Semua status'}.entries)
            ChoiceChip(label: Text(entry.value), selected: vm.weatherStatus == entry.key,
              onSelected: (_) => vm.setFilters(category: vm.category, radiusOnly: false, weatherStatus: entry.key)),
        ]),
      if (vm.refreshing) const LinearProgressIndicator(),
      if (vm.error != null) Card(child: Padding(padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(vm.error!),
          if (vm.lastLoadedAt != null) Text('Data terakhir dimuat ${formatLocalDateTime(vm.lastLoadedAt!)}'),
          OutlinedButton(onPressed: vm.refresh, child: const Text('Coba Lagi')),
        ]),
      )),
    ]);
  }
}

class _FeedFooter extends StatelessWidget {
  const _FeedFooter(this.vm);
  final EventFeedViewModel vm;
  @override
  Widget build(BuildContext context) {
    if (vm.initialLoading || vm.loadingMore) {
      return const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()));
    }
    if (vm.zoneRequired) {
      return Column(children: [
        const Text('Zona pantau belum aktif.'),
        OutlinedButton(onPressed: () => _editZone(context), child: const Text('Ubah Zona')),
      ]);
    }
    if (vm.items.isEmpty && vm.error == null) {
      return Padding(padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(vm.radiusOnly ? 'Belum ada informasi yang cocok dengan radius ini.'
              : 'Belum ada informasi yang cocok dengan filter ini.'),
          if (vm.meta?.sources.any((source) => source.state == 'unavailable') == true)
            const Text('Sebagian data sumber belum tersedia.'),
          Wrap(spacing: 8, children: [
            if (vm.radiusOnly) OutlinedButton(onPressed: () => vm.setFilters(
              category: vm.category, radiusOnly: false), child: const Text('Semua')),
            OutlinedButton(onPressed: () => _editZone(context), child: const Text('Ubah Zona')),
          ]),
        ]),
      );
    }
    if (vm.page?.hasMore == true) {
      return Column(children: [
        if (vm.loadMoreError != null) ...[
          Text(vm.loadMoreError!),
          if (vm.lastLoadedAt != null) Text('Data terakhir dimuat ${formatLocalDateTime(vm.lastLoadedAt!)}'),
        ],
        OutlinedButton(onPressed: vm.loadMore,
          child: Text(vm.loadMoreError == null ? 'Muat lagi' : 'Coba muat lagi')),
      ]);
    }
    return const SizedBox.shrink();
  }
}

class _EventCard extends StatelessWidget {
  const _EventCard({super.key, required this.item});
  final EventSummaryDto item;

  Widget _label(IconData icon, String text) => MergeSemantics(child: Wrap(
    spacing: 6, crossAxisAlignment: WrapCrossAlignment.center,
    children: [Icon(icon, size: 20), Text(text)],
  ));

  Widget _time(DateTime value) => Tooltip(message: formatFullTooltipDateTime(value),
    child: _label(Icons.schedule, formatLocalDateTime(value)));

  Widget _badge(BuildContext context, IconData icon, String text) => DecoratedBox(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: _label(icon, text)),
  );

  @override
  Widget build(BuildContext context) {
    final quake = item.source == 'BMKG_TEWS';
    final p = item.priority;
    final cap = item.cap;
    const levels = {'ordinary': 'Biasa', 'attention': 'Perhatian', 'high': 'Tinggi',
      'information': 'Informasi', 'unavailable': 'Belum tersedia'};
    const lifecycle = {'active': 'Aktif', 'scheduled': 'Terjadwal', 'expired': 'Kedaluwarsa',
      'cancelled': 'Dibatalkan', 'superseded': 'Digantikan', 'incomplete': 'Data belum lengkap',
      'current': 'Terkini', 'historical': 'Historis', 'invalid_time': 'Waktu tidak valid'};
    final distance = p.matchDistanceKm;
    return Padding(padding: const EdgeInsets.symmetric(vertical: 6),
      child: Card(child: Padding(padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 8, runSpacing: 4, children: [
            _label(quake ? Icons.sensors : Icons.thunderstorm_outlined, quake ? 'BMKG — Gempa' : 'BMKG — Cuaca'),
            if (item.isSimulated) const SimulationBadge(),
          ]),
          const SizedBox(height: 8),
          Text(item.title, style: Theme.of(context).textTheme.titleLarge),
          _time(item.occurredAt),
          if (quake) ...[
            if (distance != null) _label(Icons.place_outlined, formatDistanceKm(distance)),
            _label(Icons.flag_outlined, p.priorityDisplay == null ? 'Prioritas belum tersedia'
                : 'Prioritas ${p.priorityDisplay} — ${levels[p.priorityLabel]}'),
          ] else ...[
            if (cap != null) for (final area in cap.areaDescriptions) Text(area),
            Wrap(spacing: 12, runSpacing: 4, children: [
              _badge(context, Icons.warning_amber, 'Keparahan: ${cap?.severity ?? 'Belum tersedia'}'),
              _badge(context, item.lifecycleStatus == 'active' ? Icons.notifications_active_outlined : Icons.info_outline,
                lifecycle[item.lifecycleStatus]!),
            ]),
            if (cap != null) ...[
              Text('Berlaku mulai ${formatLocalDateTime(cap.effective)}'),
              Text(cap.expires == null ? 'Akhir masa berlaku belum tersedia'
                  : 'Hingga ${formatLocalDateTime(cap.expires!)}'),
            ],
            _label(Icons.place_outlined, switch (p.matchMethod) {
              'inside_polygon' => 'Di dalam area peringatan',
              'near_polygon_sample' => 'Perkiraan jarak centroid/vertex (bukan irisan eksak)',
              'no_geometry' => 'Tanpa geometri poligon',
              _ => 'Jarak ke titik kejadian',
            }),
            if (distance != null) Text(formatDistanceKm(distance)),
          ],
          ExpansionTile(key: PageStorageKey(item.id), tilePadding: EdgeInsets.zero,
            expandedAlignment: Alignment.centerLeft, expandedCrossAxisAlignment: CrossAxisAlignment.start,
            title: const Text('Mengapa?'), children: [
              for (final reason in p.priorityReasons) Text(reason.text),
            ]),
          OutlinedButton(onPressed: () => context.push('/events/${item.id}'), child: const Text('Lihat Detail')),
        ]),
      )),
    );
  }
}
