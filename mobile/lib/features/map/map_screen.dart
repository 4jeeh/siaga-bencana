import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../core/routing/placeholder_page.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/time_format.dart';
import '../../core/widgets/status_banners.dart';
import '../events/event_feed_view_model.dart';
import 'map_dto.dart';
import 'map_view_model.dart';
import '../zone/zone_dto.dart';
import '../zone/zone_view_model.dart';
import '../auth/auth_view_model.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key, this.mode = 'browse', this.tileProvider});
  final String mode;
  final TileProvider? tileProvider;
  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final _latitude = TextEditingController();
  final _longitude = TextEditingController();
  final _controller = MapController();
  bool _initialized = false;
  bool _tileFailed = false;
  bool _tileFailurePending = false;
  bool _edited = false;
  LatLng? _point;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized || widget.mode != 'pick_zone') return;
    _initialized = true;
    final vm = context.read<ZoneViewModel>();
    if (validCoordinates(vm.latitude, vm.longitude)) {
      _point = LatLng(vm.latitude!, vm.longitude!);
      _latitude.text = '${vm.latitude}';
      _longitude.text = '${vm.longitude}';
    }
  }

  void _select(LatLng point) {
    final lon = ((point.longitude + 180) % 360) - 180;
    if (!validCoordinates(point.latitude, lon)) return;
    setState(() {
      _point = LatLng(canonicalCoordinate(point.latitude), canonicalLongitude(lon));
      _latitude.text = '${_point!.latitude}';
      _longitude.text = '${_point!.longitude}';
      _edited = true;
    });
  }

  void _manualChanged(String _) {
    final lat = double.tryParse(_latitude.text.trim());
    final lon = double.tryParse(_longitude.text.trim());
    setState(() {
      _edited = true;
      _point = validCoordinates(lat, lon)
          ? LatLng(canonicalCoordinate(lat!), canonicalLongitude(lon!)) : null;
    });
    if (_point != null) _controller.move(_point!, _controller.camera.zoom);
  }

  String? _coordinateError(String value, double limit) {
    if (!_edited && value.isEmpty) return null;
    final number = double.tryParse(value.trim());
    return number == null || !number.isFinite || number < -limit || number > limit
        ? 'Masukkan angka antara -${limit.toInt()} dan ${limit.toInt()}.' : null;
  }

  void _tileError() {
    if (_tileFailed || _tileFailurePending) return;
    _tileFailurePending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _tileFailed = true);
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _back() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(context.read<ZoneViewModel>().savedZone == null
          ? '/account' : '/account?edit=zone');
    }
  }

  @override
  void dispose() {
    _latitude.dispose();
    _longitude.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.mode == 'browse') return _BrowseMap(tileProvider: widget.tileProvider);
    if (widget.mode != 'pick_zone') {
      return const PlaceholderPage(title: 'Peta', icon: Icons.map_outlined);
    }
    final vm = context.watch<ZoneViewModel>();
    final simulated = context.watch<AuthViewModel>().healthMeta?.isSimulated == true;
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pilih titik'),
        leading: IconButton(onPressed: _back, tooltip: 'Kembali', icon: const Icon(Icons.arrow_back)),
      ),
      body: SafeArea(child: LayoutBuilder(builder: (context, constraints) {
        return SingleChildScrollView(child: Center(child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (simulated) const Padding(
              padding: EdgeInsets.all(16), child: Text('SIMULASI - data demo')),
            if (_tileFailed) Semantics(liveRegion: true, child: Container(
              color: colors.surfaceContainerHighest,
              padding: const EdgeInsets.all(16),
              child: const Text('Peta dasar tidak tersedia. Daftar dan koordinat tetap dapat digunakan.'),
            )),
            SizedBox(
              height: (constraints.maxHeight * 0.45).clamp(200.0, 360.0),
              child: FlutterMap(
                key: const Key('zone-map'), mapController: _controller,
                options: MapOptions(
                  initialCenter: _point ?? const LatLng(-2.5, 118),
                  initialZoom: _point == null ? 4 : 8,
                  onTap: (TapPosition _, LatLng point) => _select(point),
                ),
                children: [
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'id.ac.siaga.siaga_bencana',
                    maxNativeZoom: 19,
                    tileProvider: widget.tileProvider,
                    errorTileCallback: (_, _, _) => _tileError(),
                  ),
                  if (_point != null) ...[
                    CircleLayer(circles: [CircleMarker(
                      point: _point!, radius: vm.radiusKm * 1000.0,
                      useRadiusInMeter: true,
                      color: colors.primary.withValues(alpha: 0.12),
                      borderColor: colors.primary, borderStrokeWidth: 2,
                    )]),
                    MarkerLayer(markers: [Marker(
                      point: _point!, width: 48, height: 48,
                      child: Icon(Icons.location_on, color: colors.primary,
                        size: 40, semanticLabel: 'Titik pantau terpilih'),
                    )]),
                  ],
                ],
              ),
            ),
            const Padding(padding: EdgeInsets.all(8),
              child: Text('\u00a9 OpenStreetMap contributors')),
            Padding(padding: const EdgeInsets.all(24), child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Ketuk peta atau masukkan koordinat. Pilihan belum disimpan ke server.'),
                const SizedBox(height: 16),
                TextField(
                  key: const Key('zone-latitude'), controller: _latitude,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                  decoration: InputDecoration(labelText: 'Lintang',
                    errorText: _coordinateError(_latitude.text, 90)),
                  onChanged: _manualChanged,
                ),
                const SizedBox(height: 16),
                TextField(
                  key: const Key('zone-longitude'), controller: _longitude,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                  decoration: InputDecoration(labelText: 'Bujur',
                    errorText: _coordinateError(_longitude.text, 180)),
                  onChanged: _manualChanged,
                ),
                const SizedBox(height: 16),
                if (_point == null) const Text('Konfirmasi belum tersedia: masukkan kedua koordinat yang valid.'),
                FilledButton(
                  key: const Key('confirm-point'),
                  onPressed: _point == null || vm.busy ? null : () {
                    vm.selectPoint(_point!.latitude, _point!.longitude);
                    _back();
                  },
                  child: const Text('Konfirmasi titik'),
                ),
                const SizedBox(height: 8),
                OutlinedButton(onPressed: _back, child: const Text('Batal')),
              ],
            )),
          ]),
        )));
      })),
    );
  }
}

enum _Symbol {
  zone('Titik pantau', Icons.my_location, AppColors.primary),
  quake('Gempa', Icons.waves, AppColors.warning),
  weather('Cuaca', Icons.thunderstorm_outlined, AppColors.information),
  report('Warga', Icons.campaign_outlined, AppColors.success);

  const _Symbol(this.label, this.icon, this.color);
  final String label;
  final IconData icon;
  final Color color;

  static _Symbol forMarker(MapMarkerDto m) => m.kind == 'report' ? report
      : m.source == 'BMKG_NOWCAST' ? weather : quake;
  Widget get glyph => Icon(icon, color: color);
}

String _sourceLabel(MapMarkerDto m) => m.kind == 'report'
    ? 'Warga — ditinjau admin aplikasi'
    : m.source == 'BMKG_NOWCAST' ? 'BMKG — Cuaca' : 'BMKG — Gempa';

class _BrowseMap extends StatefulWidget {
  const _BrowseMap({this.tileProvider});
  final TileProvider? tileProvider;

  @override
  State<_BrowseMap> createState() => _BrowseMapState();
}

class _BrowseMapState extends State<_BrowseMap> {
  final _controller = MapController();
  bool _tileFailed = false;
  bool _tileFailurePending = false;

  void _tileError() {
    if (_tileFailurePending) return;
    _tileFailurePending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _tileFailed = true);
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _openMarker(MapMarkerDto marker) async {
    final detail = await showModalBottomSheet<bool>(
      context: context, isScrollControlled: true, useSafeArea: true,
      builder: (sheet) => SafeArea(child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            _Symbol.forMarker(marker).glyph, Text(_sourceLabel(marker)),
            if (marker.isSimulated) const SimulationBadge(),
          ]),
          const SizedBox(height: 12),
          Text(marker.title, style: Theme.of(sheet).textTheme.titleLarge),
          Text(markerCategories[marker.category]!),
          Text(formatDistanceKm(marker.matchDistanceKm)),
          Text('Koordinat: ${marker.latitude}, ${marker.longitude}'),
          if (marker.priorityLabel != null) Text('Prioritas: ${marker.priorityLabel}'),
          if (marker.source == 'BMKG_NOWCAST')
            const Text('Titik representatif area (bukan pusat bahaya). Lihat poligon penuh di Detail Bencana.'),
          const SizedBox(height: 12),
          if (marker.kind == 'event')
            FilledButton(onPressed: () => Navigator.pop(sheet, true), child: const Text('Detail Bencana'))
          else
            const Text('Foto dan jejak verifikasi penuh tersedia di Slice 4B.'),
        ]),
      )),
    );
    if (detail == true && mounted) context.push('/events/${marker.id}');
  }

  Widget _map(MapViewModel vm, ZoneDto? zone) {
    final point = zone == null ? null : LatLng(zone.latitude, zone.longitude);
    return FlutterMap(
      mapController: _controller,
      options: MapOptions(
        initialCenter: point ?? const LatLng(-2.5, 118),
        initialZoom: point == null ? 4 : 9,
        onMapReady: () {
          if (!mounted) return;
          final bbox = formatViewportBbox(_controller.camera.visibleBounds);
          vm.onViewportChanged(bbox);
          vm.ensureInitialLoad(fallbackBbox: bbox);
        },
        onPositionChanged: (camera, _) => vm.onViewportChanged(formatViewportBbox(camera.visibleBounds)),
        onMapEvent: (event) {
          if (mounted && event is MapEventNonRotatedSizeChange && !event.camera.nonRotatedSize.isEmpty) {
            vm.onViewportChanged(formatViewportBbox(event.camera.visibleBounds));
          }
        },
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'id.ac.siaga.siaga_bencana',
          tileProvider: widget.tileProvider,
          errorTileCallback: (_, _, _) => _tileError(),
        ),
        if (zone != null)
          CircleLayer<Object>(circles: [CircleMarker(
            point: LatLng(zone.latitude, zone.longitude), radius: zone.radiusKm * 1000.0, useRadiusInMeter: true,
            color: AppColors.primary.withValues(alpha: 0.12),
            borderColor: AppColors.primary, borderStrokeWidth: 2,
          )]),
        MarkerLayer(markers: [
          if (point != null) Marker(point: point, width: 48, height: 48,
            child: Semantics(label: 'Titik pantau', child: _Symbol.zone.glyph)),
          for (final marker in vm.items)
            Marker(point: LatLng(marker.latitude, marker.longitude), width: 48, height: 48,
              child: Semantics(
                label: '${_sourceLabel(marker)}, ${marker.title}', button: true,
                child: IconButton(key: ValueKey('pin-${marker.id}'),
                  style: IconButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.surface),
                  icon: _Symbol.forMarker(marker).glyph, onPressed: () => _openMarker(marker)),
              )),
        ]),
      ],
    );
  }

  Widget _filters(MapViewModel vm) => Wrap(
    spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      SegmentedButton<bool>(
        style: SegmentedButton.styleFrom(minimumSize: const Size(48, 48)),
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(value: true, icon: Icon(Icons.near_me_outlined), label: Text('Sekitar')),
          ButtonSegment(value: false, icon: Icon(Icons.public), label: Text('Semua')),
        ],
        selected: {vm.radiusOnly}, onSelectionChanged: (value) => vm.setRadiusOnly(value.single),
      ),
      FilterChip(label: const Text('Warga verified'), avatar: _Symbol.report.glyph,
        selected: vm.includeReports, onSelected: vm.setIncludeReports),
      PopupMenuButton<String>(
        tooltip: 'Pilih kategori',
        onSelected: (value) => vm.setCategory(value.isEmpty ? null : value),
        itemBuilder: (_) => [
          for (final entry in {'': 'Semua', ...markerCategories}.entries)
            CheckedPopupMenuItem(value: entry.key, checked: entry.key == (vm.category ?? ''),
              child: Text(entry.value)),
        ],
        child: ConstrainedBox(constraints: const BoxConstraints(minHeight: 48),
          child: Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            const Icon(Icons.filter_list), Text('Kategori: ${markerCategories[vm.category] ?? 'Semua'}'),
          ])),
      ),
    ],
  );

  Widget _header(MapViewModel vm, {bool scrollable = true}) {
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (_tileFailed && !vm.listMode) ...[
          const Text('Peta dasar tidak tersedia. Daftar dan koordinat tetap dapat digunakan.'),
          TextButton.icon(onPressed: vm.toggleListMode, icon: const Icon(Icons.view_list_outlined),
            label: const Text('Tampilkan daftar hasil')),
        ],
        if (vm.zoneRequired) ...[
          const Text('Zona pantau belum aktif.'),
          TextButton(onPressed: () => context.go('/account?edit=zone'), child: const Text('Ubah Zona')),
        ],
        if (vm.error != null) ...[
          Text(vm.error!),
          if (vm.lastLoadedAt != null) Text('Data terakhir dimuat ${formatLocalDateTime(vm.lastLoadedAt!)}'),
          TextButton(onPressed: vm.retry, child: const Text('Coba Lagi')),
        ],
        if (vm.truncated) const Text('Hasil dibatasi 100. Persempit area/filter.'),
        if (!vm.loading && vm.meta != null && vm.items.isEmpty && vm.error == null && !vm.zoneRequired) ...[
          const Text('Belum ada marker sesuai area/filter'),
          Wrap(children: [
            TextButton(onPressed: vm.expandArea, child: const Text('Perluas area')),
            TextButton(onPressed: () {
              context.read<EventFeedViewModel>().setFilters(category: null, radiusOnly: false);
              context.go('/home');
            }, child: const Text('Feed Semua')),
          ]),
        ],
        if (vm.meta != null) FreshnessBanner(sources: vm.meta!.sources, compact: true),
        _filters(vm),
      ]),
    );
    return scrollable ? SingleChildScrollView(child: content) : content;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<MapViewModel>();
    final zone = context.watch<ZoneViewModel>();
    final simulated = vm.meta?.isSimulated == true ||
        context.watch<AuthViewModel>().healthMeta?.isSimulated == true;
    return Scaffold(
      appBar: AppBar(title: const Text('Peta'), actions: [
        IconButton(
          constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
          tooltip: vm.listMode ? 'Tampilkan peta' : 'Tampilkan daftar hasil',
          onPressed: vm.toggleListMode,
          icon: Icon(vm.listMode ? Icons.map_outlined : Icons.view_list_outlined),
        ),
      ]),
      body: SafeArea(child: Center(child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960),
        child: vm.listMode
            ? Column(children: [
                if (simulated) const SimulationBanner(),
                SizedBox(height: 4, child: vm.loading ? const LinearProgressIndicator() : null),
                Expanded(child: ListView.builder(
                  padding: const EdgeInsets.only(bottom: 16),
                  itemCount: vm.items.length + 2,
                  itemBuilder: (_, index) {
                    if (index == 0) return _header(vm, scrollable: false);
                    if (index > vm.items.length) {
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                        child: Wrap(spacing: 12, runSpacing: 4, alignment: WrapAlignment.center, children: [
                          for (final symbol in _Symbol.values)
                            Wrap(spacing: 4, crossAxisAlignment: WrapCrossAlignment.center,
                              children: [symbol.glyph, Text(symbol.label)]),
                        ]),
                      );
                    }
                    final marker = vm.items[index - 1];
                    return ListTile(key: ValueKey(marker.id), leading: _Symbol.forMarker(marker).glyph,
                      title: Text(marker.title), subtitle: Text('${_sourceLabel(marker)}\n'
                          '${formatDistanceKm(marker.matchDistanceKm)} · ${marker.latitude}, ${marker.longitude}'),
                      onTap: () => _openMarker(marker));
                  },
                )),
              ])
            : LayoutBuilder(builder: (context, box) {
                // Keep the map usable even when large text makes the controls taller.
                final height = box.maxHeight.clamp(480.0, double.infinity);
                final body = SizedBox(height: height, child: Column(children: [
                  SizedBox(height: height * 0.36, width: double.infinity, child: Column(children: [
                    if (simulated) const SimulationBanner(),
                    Expanded(child: _header(vm)),
                  ])),
                  SizedBox(height: 4, child: vm.loading ? const LinearProgressIndicator() : null),
                  Expanded(child: zone.loading && zone.savedZone == null
                      ? const SizedBox.shrink()
                      : _map(vm, zone.savedZone)),
                  const Text('© OpenStreetMap contributors'),
                  Wrap(spacing: 12, alignment: WrapAlignment.center, children: [
                    for (final symbol in _Symbol.values)
                      Wrap(spacing: 4, crossAxisAlignment: WrapCrossAlignment.center,
                        children: [symbol.glyph, Text(symbol.label)]),
                  ]),
                ]));
                return height > box.maxHeight ? SingleChildScrollView(child: body) : body;
              }),
      ))),
    );
  }
}
