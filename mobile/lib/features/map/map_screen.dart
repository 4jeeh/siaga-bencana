import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../core/routing/placeholder_page.dart';
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
