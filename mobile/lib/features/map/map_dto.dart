import 'dart:math' as math;

import 'package:flutter_map/flutter_map.dart';

import '../events/event_dto.dart';

const markerCategories = {
  'earthquake': 'Gempa',
  'extreme_weather': 'Cuaca Ekstrem',
  'flood': 'Banjir',
  'eruption': 'Erupsi',
  'haze_other': 'Kabut Asap/Lainnya',
};

class MapMarkerDto {
  const MapMarkerDto({
    required this.id, required this.kind, required this.source,
    required this.category, required this.title, required this.latitude,
    required this.longitude, required this.matchMethod, required this.matchDistanceKm,
    required this.priorityLabel, required this.isSimulated,
    this.magnitude, this.depthKm, this.potential,
  });

  final String id, kind, source, category, title, matchMethod;
  final double latitude, longitude, matchDistanceKm;
  final String? priorityLabel, potential;
  final double? magnitude, depthKm;
  final bool isSimulated;

  factory MapMarkerDto.fromJson(Map<String, dynamic> json) {
    String choice(String key, Iterable<String> allowed) {
      final value = json[key];
      if (value is String && allowed.contains(value)) return value;
      throw FormatException('Invalid $key');
    }
    double number(String key, double min, double max) {
      final value = json[key];
      if (value is num && value.isFinite && value >= min && value <= max) {
        return value.toDouble();
      }
      throw FormatException('Invalid $key');
    }
    final id = json['id'];
    final title = json['title'];
    final isSimulated = json['is_simulated'];
    if (id is! String || title is! String || isSimulated is! bool) {
      throw const FormatException('Invalid marker');
    }
    final potential = json['potential'];
    if (potential != null && potential is! String) throw const FormatException('Invalid potential');
    return MapMarkerDto(
      magnitude: json['magnitude'] == null ? null : number('magnitude', -double.maxFinite, double.maxFinite),
      depthKm: json['depth_km'] == null ? null : number('depth_km', 0, double.maxFinite),
      potential: potential as String?,
      id: id,
      kind: choice('kind', const ['event', 'report']),
      source: choice('source', const ['BMKG_TEWS', 'BMKG_NOWCAST', 'CITIZEN']),
      category: choice('category', markerCategories.keys),
      title: title,
      latitude: number('latitude', -90, 90),
      longitude: number('longitude', -180, 180),
      matchMethod: choice('match_method', const ['point_distance', 'inside_polygon', 'near_polygon_sample']),
      matchDistanceKm: number('match_distance_km', 0, double.maxFinite),
      priorityLabel: json['priority_label'] == null ? null : choice('priority_label',
          const ['ordinary', 'attention', 'high', 'information', 'unavailable']),
      isSimulated: isSimulated,
    );
  }
}

class MarkerFeedDto {
  const MarkerFeedDto({required this.items, required this.truncated, required this.cap, required this.meta});
  final List<MapMarkerDto> items;
  final bool truncated;
  final int cap;
  final EventMetaDto meta;

  factory MarkerFeedDto.fromJson(Map<String, dynamic> json) {
    final cap = json['cap'];
    if (cap is! int || cap != 100) throw const FormatException('Invalid cap');
    return MarkerFeedDto(
      items: (json['items'] as List<dynamic>).cast<Map<String, dynamic>>()
          .map(MapMarkerDto.fromJson).toList(growable: false),
      truncated: json['truncated'] as bool,
      cap: cap,
      meta: EventMetaDto.fromJson(json['meta'] as Map<String, dynamic>),
    );
  }
}

String formatViewportBbox(LatLngBounds bounds) {
  var west = -180.0;
  var east = 180.0;
  if (bounds.longitudeWidth < 360) {
    final half = bounds.longitudeWidth / 2;
    west = bounds.longitudeCenter - half;
    east = bounds.longitudeCenter + half;
    if (west < -180) west += 360;
    if (east > 180) east -= 360;
  }
  final south = math.min(bounds.south, bounds.north).clamp(-90, 90);
  final north = math.max(bounds.south, bounds.north).clamp(-90, 90);
  return [west, south, east, north].map((n) => n == 0 ? '0' : n.toString()).join(',');
}
