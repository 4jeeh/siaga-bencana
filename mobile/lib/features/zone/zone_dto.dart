bool validCoordinates(double? latitude, double? longitude) =>
    latitude != null && longitude != null &&
    latitude.isFinite && longitude.isFinite &&
    latitude >= -90 && latitude <= 90 &&
    longitude >= -180 && longitude <= 180;

double canonicalCoordinate(double value) => value == 0 ? 0.0 : value;
double canonicalLongitude(double value) =>
    value == 180 ? -180.0 : canonicalCoordinate(value);

class LocationSuggestionDto {
  const LocationSuggestionDto({required this.label, required this.subtitle,
    required this.latitude, required this.longitude, required this.source});
  final String label, subtitle, source;
  final double latitude, longitude;

  factory LocationSuggestionDto.fromJson(Map<String, dynamic> json) {
    if (json case {'label': String label, 'subtitle': String subtitle,
        'source': String source, 'latitude': num lat, 'longitude': num lon}
        when label.trim().isNotEmpty && validCoordinates(lat.toDouble(), lon.toDouble())) {
      return LocationSuggestionDto(label: label, subtitle: subtitle, source: source,
        latitude: lat.toDouble(), longitude: lon.toDouble());
    }
    throw const FormatException('Hasil pencarian wilayah tidak valid.');
  }
}

class ZoneUpdateRequest {
  const ZoneUpdateRequest({
    required this.latitude,
    required this.longitude,
    this.radiusKm = 50,
    this.notifyEarthquake = true,
    this.notifyWeather = true,
  });
  final double latitude;
  final double longitude;
  final int radiusKm;
  final bool notifyEarthquake;
  final bool notifyWeather;

  Map<String, dynamic> toJson() {
    if (!validCoordinates(latitude, longitude) ||
        ![25, 50, 100].contains(radiusKm)) {
      throw const FormatException('Koordinat atau radius tidak valid.');
    }
    return {
      'latitude': canonicalCoordinate(latitude),
      'longitude': canonicalLongitude(longitude),
      'radius_km': radiusKm,
      'notify_earthquake': notifyEarthquake,
      'notify_weather': notifyWeather,
    };
  }
}

class ZoneDto {
  const ZoneDto({
    required this.id,
    required this.latitude,
    required this.longitude,
    required this.radiusKm,
    required this.notifyEarthquake,
    required this.notifyWeather,
    required this.zoneVersion,
    required this.alertEligibleSince,
    required this.updatedAt,
  });
  final String id;
  final double latitude;
  final double longitude;
  final int radiusKm;
  final bool notifyEarthquake;
  final bool notifyWeather;
  final int zoneVersion;
  final DateTime alertEligibleSince;
  final DateTime updatedAt;

  factory ZoneDto.fromJson(Map<String, dynamic> json) {
    final latitude = (json['latitude'] as num).toDouble();
    final longitude = (json['longitude'] as num).toDouble();
    final radius = json['radius_km'] as int;
    final version = json['zone_version'] as int;
    if (!validCoordinates(latitude, longitude) || longitude == 180 ||
        ![25, 50, 100].contains(radius) || version < 1) {
      throw const FormatException('Respons zona tidak valid.');
    }
    return ZoneDto(
      id: json['id'] as String,
      latitude: canonicalCoordinate(latitude),
      longitude: canonicalLongitude(longitude),
      radiusKm: radius,
      notifyEarthquake: json['notify_earthquake'] as bool,
      notifyWeather: json['notify_weather'] as bool,
      zoneVersion: version,
      alertEligibleSince: DateTime.parse(json['alert_eligible_since'] as String).toUtc(),
      updatedAt: DateTime.parse(json['updated_at'] as String).toUtc(),
    );
  }
}
