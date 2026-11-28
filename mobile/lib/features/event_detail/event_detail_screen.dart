import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/labels.dart';
import '../../core/utils/time_format.dart';
import '../../core/widgets/status_banners.dart';
import '../../core/widgets/ui_kit.dart';
import '../auth/auth_view_model.dart';
import '../events/event_dto.dart';
import '../reports/report_panel.dart';
import '../zone/zone_view_model.dart';
import 'event_detail_view_model.dart';

const _missing = 'Tidak tersedia dari sumber';

String _match(PriorityDto p) => switch (p.matchMethod) {
  'inside_polygon' => 'Titik pantau berada dalam area',
  'near_polygon_sample' when p.withinRadius == true =>
    'Dekat area peringatan — perkiraan centroid/vertex',
  'near_polygon_sample' when p.withinRadius == false =>
    'Di luar radius menurut sampel centroid/vertex',
  'point_distance' when p.matchDistanceKm != null => formatDistanceKm(
    p.matchDistanceKm!,
  ),
  _ => 'Kecocokan lokasi belum tersedia',
};

Uri? _webUri(String? value) {
  final uri = value == null ? null : Uri.tryParse(value);
  if (uri == null ||
      !{'https', 'http'}.contains(uri.scheme) ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty) {
    return null;
  }
  return uri;
}

Widget _field(String name, Object? value) => Padding(
  padding: const EdgeInsets.only(top: 8),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
      Text(value?.toString() ?? _missing),
    ],
  ),
);

class _Section extends StatelessWidget {
  const _Section(this.title, this.children);
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpace.m),
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: AppSpace.s),
            ...children,
          ],
        ),
      ),
    ),
  );
}

class EventDetailScreen extends StatefulWidget {
  const EventDetailScreen({
    super.key,
    required this.eventId,
    this.tileProvider,
  });
  final String eventId;
  final TileProvider? tileProvider;

  @override
  State<EventDetailScreen> createState() => _EventDetailScreenState();
}

class _EventDetailScreenState extends State<EventDetailScreen> {
  @override
  void initState() {
    super.initState();
    _scheduleLoad();
  }

  @override
  void didUpdateWidget(EventDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.eventId != widget.eventId) _scheduleLoad();
  }

  void _scheduleLoad() {
    final id = widget.eventId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.eventId == id) {
        context.read<EventDetailViewModel>().load(id);
      }
    });
  }

  void _back() => context.canPop() ? context.pop() : context.go('/home');

  Future<void> _reference(String id) async {
    await context.push('/events/${Uri.encodeComponent(id)}');
    if (mounted && ModalRoute.of(context)?.isCurrent == true) {
      await context.read<EventDetailViewModel>().load(widget.eventId);
    }
  }

  void _source(Uri uri) {
    showDialog<void>(
      context: context,
      builder: (dialog) => AlertDialog(
        scrollable: true,
        title: const Text('Sumber resmi'),
        content: SelectableText(uri.toString()),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: uri.toString()));
              if (dialog.mounted) Navigator.pop(dialog);
            },
            child: const Text('Salin URL'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('Tutup'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<EventDetailViewModel>();
    final current = vm.currentEventId == widget.eventId;
    final detail = current ? vm.detail : null;
    final meta = current ? vm.meta : null;
    final simulation =
        context.watch<AuthViewModel>().healthMeta?.isSimulated == true;
    final loading = !current || vm.initialLoading;
    final url = _webUri(detail?.weather?.webUrl ?? detail?.sourceUrl);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Kembali',
          onPressed: _back,
          icon: const Icon(Icons.arrow_back),
        ),
        toolbarHeight: MediaQuery.textScalerOf(context).scale(22) > 30
            ? 112
            : kToolbarHeight,
        title: const Text('Detail Bencana', maxLines: 2),
        actions: [
          IconButton(
            tooltip: 'Muat ulang',
            onPressed: loading || vm.refreshing ? null : vm.refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: LayoutBuilder(
              builder: (context, bounds) => ListView(
                key: ValueKey('detail-list-${widget.eventId}'),
                padding: EdgeInsets.all(bounds.maxWidth < 400 ? 12 : 20),
                children: [
                  if (simulation ||
                      detail?.isSimulated == true ||
                      meta?.isSimulated == true)
                    const Padding(
                      padding: EdgeInsets.only(bottom: AppSpace.s),
                      child: SimulationBanner(),
                    ),
                  if (meta != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpace.s),
                      child: FreshnessBanner(sources: meta.sources),
                    ),
                  if (loading || vm.refreshing)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpace.s),
                      child: Semantics(
                        liveRegion: true,
                        child: Text(
                          loading ? 'Memuat detail…' : 'Memperbarui detail…',
                        ),
                      ),
                    ),
                  if (current && vm.notFound)
                    _Section('Informasi tidak tersedia', [
                      OutlinedButton(
                        onPressed: _back,
                        child: const Text('Kembali'),
                      ),
                    ])
                  else if (current && vm.zoneRequired)
                    _Section('Zona pantau belum aktif.', [
                      OutlinedButton(
                        onPressed: () => context.go('/account?edit=zone'),
                        child: const Text('Ubah Zona'),
                      ),
                    ])
                  else ...[
                    if (current && vm.error != null)
                      _Section('Gagal memuat detail', [
                        reportNotice(vm.error!),
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
                      ]),
                    if (detail != null) ...[
                      _header(detail),
                      if (detail.earthquake case final quake?) ...[
                        MetricStrip(
                          tiles: [
                            MetricTile(
                              label: 'Magnitudo',
                              value: quake.magnitude == null
                                  ? null
                                  : 'M ${quake.magnitude!.toStringAsFixed(1)}',
                            ),
                            MetricTile(
                              label: 'Kedalaman',
                              value: quake.depthKm == null
                                  ? null
                                  : '${quake.depthKm!.toStringAsFixed(1)} km',
                            ),
                            MetricTile(
                              label: 'Jarak',
                              value: detail.priority.matchDistanceKm == null
                                  ? null
                                  : formatDistanceKm(
                                      detail.priority.matchDistanceKm!,
                                    ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpace.m),
                        TsunamiPotentialBox(potential: quake.potential),
                        const SizedBox(height: AppSpace.m),
                      ],
                      _priority(detail),
                      if (detail.earthquake != null)
                        _radarScoreExplanation(detail.priority),
                      if (detail.earthquake case final quake?)
                        _earthquake(quake),
                      if (detail.weather case final weather?)
                        _weather(detail, weather),
                      _MiniMap(
                        key: ObjectKey(detail),
                        detail: detail,
                        tileProvider: widget.tileProvider,
                      ),
                      Wrap(
                        spacing: AppSpace.s,
                        runSpacing: AppSpace.s,
                        children: [
                          OutlinedButton.icon(
                            onPressed: url == null ? null : () => _source(url),
                            icon: const Icon(Icons.open_in_new),
                            label: const Text('Buka sumber resmi'),
                          ),
                          FilledButton.icon(
                            onPressed: () => context.go(
                              Uri(
                                path: '/reports',
                                queryParameters: {'event_id': detail.id},
                              ).toString(),
                            ),
                            icon: const Icon(Icons.campaign_outlined),
                            label: const Text('Laporkan kondisi terkait'),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpace.m),
                      _Section('Laporan warga terkait', [
                        Text(
                          'Warga — ditinjau admin aplikasi',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        if (vm.relatedReportsLoading)
                          const LinearProgressIndicator()
                        else if (vm.relatedReportsError != null)
                          reportNotice(vm.relatedReportsError!)
                        else if (vm.relatedReports.isEmpty)
                          const Text(
                            'Belum ada laporan warga ditinjau yang terkait',
                          ),
                        for (final report in vm.relatedReports) ...[
                          Text(report.description),
                          Semantics(
                            button: true,
                            label: 'Lihat laporan ${report.category}',
                            excludeSemantics: true,
                            child: OutlinedButton(
                              onPressed: () => showReportPanel(context, report),
                              child: const Text('Lihat'),
                            ),
                          ),
                        ],
                      ]),
                    ],
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(EventDetailDto d) {
    final quake = d.earthquake != null;
    return _Section(d.title, [
      Wrap(
        spacing: AppSpace.s,
        runSpacing: AppSpace.s,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          IconLabel(
            icon: quake ? Icons.sensors : Icons.thunderstorm_outlined,
            text: quake ? 'BMKG — Gempa' : 'BMKG — Cuaca',
            color: AppColors.textMuted,
          ),
          if (d.isSimulated) const SimulationBadge(),
          StatusPill(
            icon: Icons.schedule,
            label: lifecycleLabels[d.lifecycleStatus]!,
            foreground: AppColors.textPrimary,
            background: AppColors.surfaceVariant,
          ),
        ],
      ),
      if (!quake && d.lifecycleStatus != 'active')
        const Padding(
          padding: EdgeInsets.only(top: AppSpace.s),
          child: Text('Peringatan tidak aktif.'),
        ),
      _field('Waktu kejadian', formatLocalDateTime(d.occurredAt)),
      _field('Pertama tercatat', formatLocalDateTime(d.firstSeenAt)),
      _field('Terakhir terlihat di sumber', formatLocalDateTime(d.lastSeenAt)),
    ]);
  }

  Widget _priority(EventDetailDto d) {
    final p = d.priority;
    final quakeColor = switch (p.priorityLabel) {
      'high' => AppColors.error,
      'attention' => AppColors.warning,
      'ordinary' => AppColors.primary,
      _ => AppColors.textMuted,
    };
    return _Section('Prioritas informasi', [
      if (d.earthquake != null)
        Align(
          alignment: Alignment.centerLeft,
          child: StatusPill(
            icon: Icons.flag_outlined,
            label: p.priorityDisplay == null
                ? 'Prioritas belum tersedia'
                : 'Prioritas ${p.priorityDisplay} — ${priorityLevelLabels[p.priorityLabel]}',
            foreground: quakeColor,
            background: quakeColor.withValues(alpha: 0.10),
            textColor: quakeColor == AppColors.warning
                ? AppColors.textPrimary
                : null,
          ),
        )
      else
        Wrap(
          spacing: AppSpace.s,
          runSpacing: AppSpace.s,
          children: [
            StatusPill(
              icon: Icons.warning_amber,
              label:
                  'Keparahan: ${capSeverityLabel(d.cap?.severity) ?? _missing}',
              foreground: AppColors.warning,
              background: AppColors.warning.withValues(alpha: 0.10),
              textColor: AppColors.textPrimary,
            ),
            StatusPill(
              icon: Icons.flag_outlined,
              label: 'Prioritas: ${priorityLevelLabels[p.priorityLabel]}',
              foreground: AppColors.primary,
              background: AppColors.primaryContainer,
            ),
          ],
        ),
      const SizedBox(height: AppSpace.s),
      IconLabel(icon: Icons.place_outlined, text: _match(p)),
      const SizedBox(height: AppSpace.s),
      DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: ExpansionTile(
          key: PageStorageKey('detail-why-${d.id}'),
          shape: const Border(),
          collapsedShape: const Border(),
          leading: const Icon(Icons.help_outline, size: 20),
          title: const Text('Mengapa?'),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          children: [
            for (final reason in p.priorityReasons)
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: IconLabel(
                    icon: Icons.chevron_right,
                    text: reason.text,
                    iconSize: 16,
                  ),
                ),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: _field(
                'Waktu evaluasi',
                formatLocalDateTime(p.evaluatedAt),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: AppSpace.s),
      Text(
        'Prioritas informasi aplikasi, bukan penilaian risiko ilmiah. Di luar radius bukan berarti aman.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ]);
  }

  Widget _radarScoreExplanation(PriorityDto p) {
    final c = p.components;
    Widget bentoTile(
      String title,
      String formula,
      String? compKey,
      int w, {
      required bool compactRow,
    }) {
      final raw = c?[compKey];
      final detail = raw == null
          ? null
          : 'nilai ${raw.toStringAsFixed(2)} → ${(w * raw).toStringAsFixed(1)} poin';
      final detailStyle = Theme.of(context).textTheme.labelMedium?.copyWith(
        color: AppColors.primary,
        fontWeight: FontWeight.w700,
        fontFeatures: tabularFigures,
      );
      return DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.outline),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.m),
          child: compactRow
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            formula,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    if (detail != null) ...[
                      const SizedBox(width: AppSpace.m),
                      Flexible(
                        child: Text(
                          detail,
                          textAlign: TextAlign.right,
                          style: detailStyle,
                        ),
                      ),
                    ],
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 2),
                    Text(formula, style: Theme.of(context).textTheme.bodySmall),
                    if (detail != null) ...[
                      const SizedBox(height: AppSpace.xs),
                      Text(detail, style: detailStyle),
                    ],
                  ],
                ),
        ),
      );
    }

    return _Section('Cara skor Radar Radius dihitung', [
      DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.m),
          child: Center(
            child: Text(
              'S = 60P + 25M + 15T',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                fontFeatures: tabularFigures,
              ),
            ),
          ),
        ),
      ),
      const SizedBox(height: AppSpace.m),
      LayoutBuilder(
        builder: (context, constraints) {
          final fitsRow =
              constraints.maxWidth >=
              MediaQuery.textScalerOf(context).scale(480);
          final tiles = [
            bentoTile(
              'P · Kedekatan',
              '60% · 1 − jarak/radius',
              'p',
              60,
              compactRow: !fitsRow,
            ),
            bentoTile(
              'M · Magnitudo',
              '25% · M/10',
              'm',
              25,
              compactRow: !fitsRow,
            ),
            bentoTile(
              'T · Kebaruan',
              '15% · 1 − umur jam/24',
              't',
              15,
              compactRow: !fitsRow,
            ),
          ];
          if (fitsRow) {
            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < tiles.length; i++) ...[
                    if (i > 0) const SizedBox(width: AppSpace.s),
                    Expanded(child: tiles[i]),
                  ],
                ],
              ),
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < tiles.length; i++) ...[
                if (i > 0) const SizedBox(height: AppSpace.s),
                tiles[i],
              ],
            ],
          );
        },
      ),
      const SizedBox(height: AppSpace.m),
      Text(
        'Biasa < 35 · Perhatian 35–65 · Tinggi ≥ 65',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ]);
  }

  Widget _earthquake(EarthquakeDetailDto q) {
    final image = _webUri(q.shakemapUrl);
    return _Section('Atribut gempa', [
      _field('Wilayah', q.region),
      _field(
        'Koordinat',
        q.latitudeText == null && q.longitudeText == null
            ? null
            : '${q.latitudeText ?? _missing}, ${q.longitudeText ?? _missing}',
      ),
      _field('Dirasakan', q.felt),
      _field('Shakemap', q.shakemapUrl),
      if (image != null)
        Padding(
          padding: const EdgeInsets.only(top: AppSpace.m),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: Image.network(
              image.toString(),
              semanticLabel: 'Shakemap BMKG',
              loadingBuilder: (context, child, progress) => progress == null
                  ? child
                  : const Padding(
                      padding: EdgeInsets.symmetric(vertical: AppSpace.l),
                      child: Center(child: CircularProgressIndicator()),
                    ),
              errorBuilder: (_, _, _) => const Text(
                'Pratinjau shakemap tidak dapat dimuat. Detail teks tetap tersedia.',
              ),
            ),
          ),
        ),
    ]);
  }

  Widget _weather(EventDetailDto d, WeatherDetailDto w) {
    final cap = d.cap;
    return _Section('Atribut cuaca', [
      _field('Jenis kejadian', w.capEvent),
      _field('Keparahan', capSeverityLabel(cap?.severity)),
      _field('Urgensi', capUrgencyLabel(cap?.urgency)),
      _field('Kepastian', capCertaintyLabel(cap?.certainty)),
      _field(
        'Masa berlaku',
        '${cap == null ? _missing : formatLocalDateTime(cap.effective)} s.d. '
            '${cap?.expires == null ? _missing : formatLocalDateTime(cap!.expires!)}',
      ),
      _field('Tipe / Status pesan', '${w.msgType} / ${w.status}'),
      Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          w.lifecycleComplete
              ? 'Siklus hidup lengkap'
              : 'Siklus hidup belum lengkap',
        ),
      ),
      _field(
        'Wilayah terdampak',
        cap == null || cap.areaDescriptions.isEmpty
            ? null
            : cap.areaDescriptions.join(', '),
      ),
      _field('Judul', w.headline),
      _field('Deskripsi', w.description),
      const SizedBox(height: AppSpace.m),
      Semantics(header: true, child: const Text('Rujukan')),
      if (d.references.isEmpty) const Text('Tidak ada rujukan'),
      for (final ref in d.references) ...[
        Text('${ref.relationType} — ${ref.referencedSourceKey}'),
        if (ref.referencedEventId case final id?)
          OutlinedButton(
            onPressed: () => _reference(id),
            child: const Text('Lihat event rujukan'),
          ),
      ],
    ]);
  }
}

class _MiniMap extends StatefulWidget {
  const _MiniMap({super.key, required this.detail, this.tileProvider});
  final EventDetailDto detail;
  final TileProvider? tileProvider;

  @override
  State<_MiniMap> createState() => _MiniMapState();
}

class _MiniMapState extends State<_MiniMap> {
  bool _tileFailed = false;

  void _onTileError() {
    if (_tileFailed || !mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_tileFailed) setState(() => _tileFailed = true);
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.detail;
    final zone = context.watch<ZoneViewModel>().savedZone;
    final rings = [
      for (final a in d.areas)
        for (final p in a.polygons)
          if (p.geometryValid && p.vertices.length >= 3) p,
    ];
    final point = d.latitude != null && d.longitude != null
        ? LatLng(d.latitude!, d.longitude!)
        : null;
    final center =
        point ??
        (rings.isEmpty
            ? null
            : LatLng(
                rings.first.centroidLatitude!,
                rings.first.centroidLongitude!,
              ));
    final pointLabel = d.weather != null
        ? 'Titik representatif area'
        : 'Titik kejadian';
    final color = Theme.of(context).colorScheme.primary;
    final bodySmall = Theme.of(context).textTheme.bodySmall;
    return _Section('Peta mini', [
      for (final area in d.areas) Text(area.areaDescription, style: bodySmall),
      _field(
        pointLabel,
        center == null ? null : '${center.latitude}, ${center.longitude}',
      ),
      if (zone != null)
        _field(
          'Titik pantau',
          '${zone.latitude}, ${zone.longitude} · Radius ${zone.radiusKm} km',
        ),
      const SizedBox(height: AppSpace.s),
      IconLabel(icon: Icons.place_outlined, text: _match(d.priority)),
      if (center != null) ...[
        const SizedBox(height: AppSpace.m),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: AspectRatio(
            aspectRatio: 1.6,
            child: FlutterMap(
              options: MapOptions(
                initialCenter: center,
                initialZoom: 7,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.none,
                ),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  tileProvider: widget.tileProvider,
                  userAgentPackageName: 'id.ac.siaga.siaga_bencana',
                  errorTileCallback: (_, _, _) => _onTileError(),
                ),
                if (rings.isNotEmpty)
                  PolygonLayer<Object>(
                    // The projection wraps adjacent vertices; raw west/east bounds can
                    // exclude the visible strip at the date line during culling.
                    polygonCulling: !rings.any(
                      (ring) => ring.crossesAntimeridian == true,
                    ),
                    polygons: [
                      for (final p in rings)
                        Polygon(
                          points: [
                            for (final v in p.vertices)
                              LatLng(v.latitude, v.longitude),
                          ],
                          color: color.withValues(alpha: 0.2),
                          borderColor: color,
                          borderStrokeWidth: 2,
                        ),
                    ],
                  ),
                if (zone != null)
                  CircleLayer<Object>(
                    circles: [
                      CircleMarker(
                        point: LatLng(zone.latitude, zone.longitude),
                        radius: zone.radiusKm * 1000.0,
                        useRadiusInMeter: true,
                        color: color.withValues(alpha: 0.1),
                        borderColor: color,
                        borderStrokeWidth: 1,
                      ),
                    ],
                  ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: center,
                      child: Icon(
                        Icons.location_on,
                        color: AppColors.error,
                        size: 32,
                        semanticLabel: pointLabel,
                      ),
                    ),
                    if (zone != null)
                      Marker(
                        point: LatLng(zone.latitude, zone.longitude),
                        child: const Icon(
                          Icons.my_location,
                          color: AppColors.primary,
                          size: 24,
                          semanticLabel: 'Titik pantau',
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpace.xs),
        Text('© OpenStreetMap contributors', style: bodySmall),
        if (_tileFailed)
          const Text(
            'Peta dasar tidak tersedia. Daftar dan koordinat tetap dapat digunakan.',
          ),
      ],
    ]);
  }
}
