import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../core/utils/time_format.dart';
import '../../core/widgets/status_banners.dart';
import '../auth/auth_view_model.dart';
import '../events/event_dto.dart';
import '../zone/zone_view_model.dart';
import 'event_detail_view_model.dart';

const _missing = 'Tidak tersedia dari sumber';
const _levels = {
  'ordinary': 'Biasa',
  'attention': 'Perhatian',
  'high': 'Tinggi',
  'information': 'Informasi',
  'unavailable': 'Belum tersedia',
};
const _statuses = {
  'current': 'Terkini',
  'historical': 'Historis',
  'invalid_time': 'Waktu tidak valid',
  'active': 'Aktif',
  'scheduled': 'Terjadwal',
  'expired': 'Kedaluwarsa',
  'cancelled': 'Dibatalkan',
  'superseded': 'Digantikan',
  'incomplete': 'Data belum lengkap',
};

String _match(PriorityDto p) => switch (p.matchMethod) {
  'inside_polygon' => 'Titik pantau berada dalam area',
  'near_polygon_sample' when p.withinRadius == true =>
    'Dekat area peringatan — perkiraan centroid/vertex',
  'near_polygon_sample' when p.withinRadius == false =>
    'Di luar radius menurut sampel centroid/vertex',
  'point_distance' when p.matchDistanceKm != null => formatDistanceKm(p.matchDistanceKm!),
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

Widget _label(IconData icon, String value) => MergeSemantics(
  child: Wrap(
    spacing: 8,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [Icon(icon, size: 20), Text(value)],
  ),
);

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
    padding: const EdgeInsets.only(bottom: 12),
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(title, style: Theme.of(context).textTheme.titleLarge),
            ),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    ),
  );
}

class EventDetailScreen extends StatefulWidget {
  const EventDetailScreen({super.key, required this.eventId, this.tileProvider});
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
      if (mounted && widget.eventId == id) context.read<EventDetailViewModel>().load(id);
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
          TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('Tutup')),
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
    final simulation = context.watch<AuthViewModel>().healthMeta?.isSimulated == true;
    final loading = !current || vm.initialLoading;
    final url = _webUri(detail?.weather?.webUrl ?? detail?.sourceUrl);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Kembali',
          onPressed: _back,
          icon: const Icon(Icons.arrow_back),
        ),
        toolbarHeight: MediaQuery.textScalerOf(context).scale(22) > 30 ? 112 : kToolbarHeight,
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
                  if (simulation || detail?.isSimulated == true || meta?.isSimulated == true)
                    const SimulationBanner(),
                  if (meta != null) FreshnessBanner(sources: meta.sources),
                  if (loading || vm.refreshing)
                    Semantics(
                      liveRegion: true,
                      child: Text(loading ? 'Memuat detail…' : 'Memperbarui detail…'),
                    ),
                  if (current && vm.notFound)
                    _Section('Informasi tidak tersedia', [
                      OutlinedButton(onPressed: _back, child: const Text('Kembali')),
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
                        Text(vm.error!),
                        if (vm.lastLoadedAt != null)
                          Text('Data terakhir dimuat ${formatLocalDateTime(vm.lastLoadedAt!)}'),
                        OutlinedButton(onPressed: vm.refresh, child: const Text('Coba Lagi')),
                      ]),
                    if (detail != null) ...[
                      _header(detail),
                      _priority(detail),
                      if (detail.earthquake case final quake?) _earthquake(quake),
                      if (detail.weather case final weather?) _weather(detail, weather),
                      _MiniMap(
                        key: ObjectKey(detail),
                        detail: detail,
                        tileProvider: widget.tileProvider,
                      ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton(
                            onPressed: url == null ? null : () => _source(url),
                            child: const Text('Buka sumber resmi'),
                          ),
                          FilledButton(
                            onPressed: () => context.go(
                              Uri(
                                path: '/reports',
                                queryParameters: {'event_id': detail.id},
                              ).toString(),
                            ),
                            child: const Text('Laporkan kondisi terkait'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const _Section('Laporan warga terkait', [
                        Text('Warga — ditinjau admin aplikasi'),
                        Text('Belum ada laporan warga ditinjau yang terkait'),
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
        spacing: 12,
        runSpacing: 6,
        children: [
          _label(
            quake ? Icons.sensors : Icons.thunderstorm_outlined,
            quake ? 'BMKG — Gempa' : 'BMKG — Cuaca',
          ),
          if (d.isSimulated) const SimulationBadge(),
          _label(Icons.schedule, _statuses[d.lifecycleStatus]!),
        ],
      ),
      if (!quake && d.lifecycleStatus != 'active') const Text('Peringatan tidak aktif.'),
      _field('Waktu kejadian', formatLocalDateTime(d.occurredAt)),
      _field('Pertama tercatat', formatLocalDateTime(d.firstSeenAt)),
      _field('Terakhir terlihat di sumber', formatLocalDateTime(d.lastSeenAt)),
    ]);
  }

  Widget _priority(EventDetailDto d) {
    final p = d.priority;
    return _Section('Prioritas informasi', [
      if (d.earthquake != null)
        _label(
          Icons.flag_outlined,
          p.priorityDisplay == null
              ? 'Prioritas belum tersedia'
              : 'Prioritas ${p.priorityDisplay} — ${_levels[p.priorityLabel]}',
        )
      else ...[
        _label(Icons.warning_amber, 'Keparahan: ${d.cap?.severity ?? _missing}'),
        _label(Icons.flag_outlined, 'Prioritas: ${_levels[p.priorityLabel]}'),
        _label(Icons.schedule, _statuses[d.lifecycleStatus]!),
      ],
      _label(Icons.place_outlined, _match(p)),
      ExpansionTile(
        key: PageStorageKey('detail-why-${d.id}'),
        title: const Text('Mengapa?'),
        children: [
          for (final reason in p.priorityReasons)
            Align(alignment: Alignment.centerLeft, child: Text(reason.text)),
          _field('Waktu evaluasi', formatLocalDateTime(p.evaluatedAt)),
        ],
      ),
      const Text(
        'Prioritas informasi aplikasi, bukan penilaian risiko ilmiah. Di luar radius bukan berarti aman.',
      ),
    ]);
  }

  Widget _earthquake(EarthquakeDetailDto q) {
    final image = _webUri(q.shakemapUrl);
    return _Section('Atribut gempa', [
      _field('Magnitudo', q.magnitude),
      _field('Kedalaman', q.depthKm == null ? null : '${q.depthKm} km'),
      _field('Wilayah', q.region),
      _field(
        'Koordinat',
        q.latitudeText == null && q.longitudeText == null
            ? null
            : '${q.latitudeText ?? _missing}, ${q.longitudeText ?? _missing}',
      ),
      _field('Potensi', q.potential),
      _field('Dirasakan', q.felt),
      _field('Shakemap', q.shakemapUrl),
      if (image != null)
        Image.network(
          image.toString(),
          semanticLabel: 'Shakemap BMKG',
          errorBuilder: (_, _, _) =>
              const Text('Pratinjau shakemap tidak dapat dimuat. Detail teks tetap tersedia.'),
        ),
    ]);
  }

  Widget _weather(EventDetailDto d, WeatherDetailDto w) {
    final cap = d.cap;
    return _Section('Atribut cuaca', [
      _field('Jenis kejadian', w.capEvent),
      _field('Severity', cap?.severity),
      _field('Urgency', cap?.urgency),
      _field('Certainty', cap?.certainty),
      _field(
        'Masa berlaku',
        '${cap == null ? _missing : formatLocalDateTime(cap.effective)} s.d. '
            '${cap?.expires == null ? _missing : formatLocalDateTime(cap!.expires!)}',
      ),
      _field('Tipe / Status pesan', '${w.msgType} / ${w.status}'),
      Text(w.lifecycleComplete ? 'Siklus hidup lengkap' : 'Siklus hidup belum lengkap'),
      _field(
        'Wilayah terdampak',
        cap == null || cap.areaDescriptions.isEmpty ? null : cap.areaDescriptions.join(', '),
      ),
      _field('Headline', w.headline),
      _field('Deskripsi', w.description),
      Semantics(header: true, child: const Text('Rujukan')),
      if (d.references.isEmpty) const Text('Tidak ada rujukan'),
      for (final ref in d.references) ...[
        Text('${ref.relationType} — ${ref.referencedSourceKey}'),
        if (ref.referencedEventId case final id?)
          OutlinedButton(onPressed: () => _reference(id), child: const Text('Lihat event rujukan')),
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
            : LatLng(rings.first.centroidLatitude!, rings.first.centroidLongitude!));
    final pointLabel = d.weather != null ? 'Titik representatif area' : 'Titik kejadian';
    final color = Theme.of(context).colorScheme.primary;
    return _Section('Peta mini', [
      for (final area in d.areas) Text(area.areaDescription),
      _field(pointLabel, center == null ? null : '${center.latitude}, ${center.longitude}'),
      if (zone != null)
        _field('Titik pantau', '${zone.latitude}, ${zone.longitude} · Radius ${zone.radiusKm} km'),
      Text(_match(d.priority)),
      if (center != null) ...[
        AspectRatio(
          aspectRatio: 1.6,
          child: FlutterMap(
            options: MapOptions(
              initialCenter: center,
              initialZoom: 7,
              interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
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
                  polygonCulling: !rings.any((ring) => ring.crossesAntimeridian == true),
                  polygons: [
                    for (final p in rings)
                      Polygon(
                        points: [for (final v in p.vertices) LatLng(v.latitude, v.longitude)],
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
                    child: Icon(Icons.location_on, semanticLabel: pointLabel),
                  ),
                  if (zone != null)
                    Marker(
                      point: LatLng(zone.latitude, zone.longitude),
                      child: const Icon(Icons.my_location, semanticLabel: 'Titik pantau'),
                    ),
                ],
              ),
            ],
          ),
        ),
        const Text('© OpenStreetMap contributors'),
        if (_tileFailed)
          const Text('Peta dasar tidak tersedia. Daftar dan koordinat tetap dapat digunakan.'),
      ],
    ]);
  }
}
