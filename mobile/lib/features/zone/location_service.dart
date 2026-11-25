import 'package:geolocator/geolocator.dart';

class ZoneLocation {
  const ZoneLocation(this.latitude, this.longitude);
  final double latitude;
  final double longitude;
}

class LocationFailure implements Exception {
  const LocationFailure(this.message, {this.canOpenSettings = false});
  final String message;
  final bool canOpenSettings;
}

abstract interface class LocationService {
  Future<ZoneLocation> locateOnce();
  Future<bool> openAppSettings();
}

abstract interface class LocationPermissionRequester {
  Future<bool> requestLocationPermission();
}

class GeolocatorLocationService implements LocationService, LocationPermissionRequester {
  const GeolocatorLocationService();

  @override
  Future<bool> requestLocationPermission() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
      return permission == LocationPermission.whileInUse || permission == LocationPermission.always;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<ZoneLocation> locateOnce() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const LocationFailure('GPS belum aktif. Aktifkan GPS atau pilih titik manual.');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      throw const LocationFailure(
        'Izin lokasi ditolak permanen. Buka Pengaturan atau pilih titik manual.',
        canOpenSettings: true,
      );
    }
    if (permission != LocationPermission.whileInUse &&
        permission != LocationPermission.always) {
      throw const LocationFailure('Izin lokasi ditolak. Pilih titik manual.');
    }
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    ).timeout(const Duration(seconds: 10));
    return ZoneLocation(position.latitude, position.longitude);
  }

  @override
  Future<bool> openAppSettings() => Geolocator.openAppSettings();
}
