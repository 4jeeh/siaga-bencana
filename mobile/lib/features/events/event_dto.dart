import '../../core/network/api_envelope.dart';

const _sourceValues = {'BMKG_TEWS', 'BMKG_NOWCAST'};
const _stateValues = {'healthy', 'degraded', 'stale', 'unavailable'};
const _algoValues = {'eq-priority-v1', 'cap-priority-v1'};
const _labelValues = {'ordinary', 'attention', 'high', 'information', 'unavailable'};
const _matchValues = {'point_distance', 'inside_polygon', 'near_polygon_sample', 'no_geometry'};
const _categoryValues = {'earthquake', 'extreme_weather'};
const _lifecycleValues = {'current', 'historical', 'invalid_time', 'active', 'scheduled', 'expired', 'cancelled', 'superseded', 'incomplete'};

String _choice(Map<String, dynamic> json, String key, Set<String> allowed) {
  final value = json[key];
  if (value is String && allowed.contains(value)) return value;
  throw FormatException('Invalid $key');
}

int _version(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is int && value >= 1) return value;
  throw FormatException('Invalid $key');
}

DateTime _date(dynamic value) => value is String
    ? DateTime.parse(value).toUtc() : throw const FormatException('Invalid date');
DateTime? _optionalDate(dynamic value) => value == null ? null : _date(value);

List<T> _objects<T>(dynamic value, T Function(Map<String, dynamic>) decode) =>
    value is List<dynamic> ? [for (final item in value)
      if (item is Map<String, dynamic>) decode(item) else throw const FormatException('Invalid object'),
    ] : throw const FormatException('Invalid list');

class SourceFreshnessDto {
  const SourceFreshnessDto({
    required this.source,
    required this.state,
    required this.lastSuccessAt,
    required this.lastAttemptAt,
  });

  final String source;
  final String state;
  final DateTime? lastSuccessAt;
  final DateTime? lastAttemptAt;

  factory SourceFreshnessDto.fromJson(Map<String, dynamic> json) {
    return SourceFreshnessDto(
      source: _choice(json, 'source', _sourceValues),
      state: _choice(json, 'state', _stateValues),
      lastSuccessAt: _optionalDate(json['last_success_at']),
      lastAttemptAt: _optionalDate(json['last_attempt_at']),
    );
  }
}

class EventMetaDto extends ApiMeta {
  const EventMetaDto({
    required super.serverTime,
    required super.mode,
    required super.isSimulated,
    required this.zoneVersion,
    required this.sources,
  });

  final int zoneVersion;
  final List<SourceFreshnessDto> sources;

  factory EventMetaDto.fromJson(Map<String, dynamic> json) {
    final meta = ApiMeta.fromJson(json);
    return EventMetaDto(
      serverTime: meta.serverTime,
      mode: meta.mode,
      isSimulated: meta.isSimulated,
      zoneVersion: _version(json, 'zone_version'),
      sources: _objects(json['sources'], SourceFreshnessDto.fromJson),
    );
  }
}

class PriorityReasonDto {
  const PriorityReasonDto({
    required this.code,
    required this.text,
    required this.values,
  });

  final String code;
  final String text;
  final Map<String, dynamic> values;

  factory PriorityReasonDto.fromJson(Map<String, dynamic> json) {
    return PriorityReasonDto(
      code: json['code'] as String,
      text: json['text'] as String,
      values: json['values'] as Map<String, dynamic>,
    );
  }
}

class PriorityDto {
  const PriorityDto({
    required this.priorityAlgo,
    required this.priorityScore,
    required this.priorityDisplay,
    required this.priorityLabel,
    required this.priorityReasons,
    required this.components,
    required this.matchMethod,
    required this.matchDistanceKm,
    required this.withinRadius,
    required this.evaluatedAt,
    required this.zoneVersion,
  });

  final String priorityAlgo;
  final double? priorityScore;
  final String? priorityDisplay;
  final String priorityLabel;
  final List<PriorityReasonDto> priorityReasons;
  final Map<String, double>? components;
  final String matchMethod;
  final double? matchDistanceKm;
  final bool? withinRadius;
  final DateTime evaluatedAt;
  final int zoneVersion;

  factory PriorityDto.fromJson(Map<String, dynamic> json) {
    return PriorityDto(
      priorityAlgo: _choice(json, 'priority_algo', _algoValues),
      priorityScore: (json['priority_score'] as num?)?.toDouble(),
      priorityDisplay: json['priority_display'] as String?,
      priorityLabel: _choice(json, 'priority_label', _labelValues),
      priorityReasons: _objects(json['priority_reasons'], PriorityReasonDto.fromJson),
      components: (json['components'] as Map<String, dynamic>?)?.map(
        (key, value) => MapEntry(key, (value as num).toDouble()),
      ),
      matchMethod: _choice(json, 'match_method', _matchValues),
      matchDistanceKm: (json['match_distance_km'] as num?)?.toDouble(),
      withinRadius: json['within_radius'] as bool?,
      evaluatedAt: _date(json['evaluated_at']),
      zoneVersion: _version(json, 'zone_version'),
    );
  }
}

class CapSummaryDto {
  const CapSummaryDto({
    required this.severity,
    required this.urgency,
    required this.certainty,
    required this.effective,
    required this.expires,
    required this.areaDescriptions,
  });

  final String? severity;
  final String? urgency;
  final String? certainty;
  final DateTime effective;
  final DateTime? expires;
  final List<String> areaDescriptions;

  factory CapSummaryDto.fromJson(Map<String, dynamic> json) {
    return CapSummaryDto(
      severity: json['severity'] as String?,
      urgency: json['urgency'] as String?,
      certainty: json['certainty'] as String?,
      effective: _date(json['effective']),
      expires: _optionalDate(json['expires']),
      areaDescriptions: List<String>.from(json['area_descriptions'] as List<dynamic>),
    );
  }
}

class EventSummaryDto {
  const EventSummaryDto({
    required this.id,
    required this.source,
    required this.category,
    required this.title,
    required this.occurredAt,
    required this.latitude,
    required this.longitude,
    required this.isSimulated,
    required this.contentVersion,
    required this.lifecycleStatus,
    required this.priority,
    required this.cap,
  });

  final String id;
  final String source;
  final String category;
  final String title;
  final DateTime occurredAt;
  final double? latitude;
  final double? longitude;
  final bool isSimulated;
  final int contentVersion;
  final String lifecycleStatus;
  final PriorityDto priority;
  final CapSummaryDto? cap;

  factory EventSummaryDto.fromJson(Map<String, dynamic> json) {
    return EventSummaryDto(
      id: json['id'] as String,
      source: _choice(json, 'source', _sourceValues),
      category: _choice(json, 'category', _categoryValues),
      title: json['title'] as String,
      occurredAt: _date(json['occurred_at']),
      latitude: _coordinate(json, 'latitude', 90),
      longitude: _coordinate(json, 'longitude', 180),
      isSimulated: json['is_simulated'] as bool,
      contentVersion: _version(json, 'content_version'),
      lifecycleStatus: _choice(json, 'lifecycle_status', _lifecycleValues),
      priority: PriorityDto.fromJson(json['priority'] as Map<String, dynamic>),
      cap: json['cap'] == null ? null : CapSummaryDto.fromJson(json['cap'] as Map<String, dynamic>),
    );
  }
}

class PageDto {
  const PageDto({
    required this.limit,
    required this.offset,
    required this.nextOffset,
    required this.hasMore,
  });

  final int limit;
  final int offset;
  final int? nextOffset;
  final bool hasMore;

  factory PageDto.fromJson(Map<String, dynamic> json) {
    return PageDto(
      limit: json['limit'] as int,
      offset: json['offset'] as int,
      nextOffset: json['next_offset'] as int?,
      hasMore: json['has_more'] as bool,
    );
  }
}

class EventFeedDto {
  const EventFeedDto({
    required this.items,
    required this.page,
    required this.meta,
  });

  final List<EventSummaryDto> items;
  final PageDto page;
  final EventMetaDto meta;

  factory EventFeedDto.fromJson(Map<String, dynamic> json) {
    return EventFeedDto(
      items: _objects(json['items'], EventSummaryDto.fromJson),
      page: PageDto.fromJson(json['page'] as Map<String, dynamic>),
      meta: EventMetaDto.fromJson(json['meta'] as Map<String, dynamic>),
    );
  }
}

T _field<T>(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is T) return value;
  throw FormatException('Invalid $key');
}

double? _coordinate(Map<String, dynamic> json, String key, double limit) {
  final value = _field<num?>(json, key)?.toDouble();
  if (value != null && (!value.isFinite || value.abs() > limit)) {
    throw FormatException('Invalid $key');
  }
  return value;
}

class EarthquakeDetailDto {
  const EarthquakeDetailDto({
    required this.magnitude,
    required this.depthKm,
    required this.region,
    required this.latitudeText,
    required this.longitudeText,
    required this.potential,
    required this.felt,
    required this.shakemapUrl,
  });

  final double? magnitude;
  final double? depthKm;
  final String? region;
  final String? latitudeText;
  final String? longitudeText;
  final String? potential;
  final String? felt;
  final String? shakemapUrl;

  factory EarthquakeDetailDto.fromJson(Map<String, dynamic> json) {
    return EarthquakeDetailDto(
      magnitude: _field<num?>(json, 'magnitude')?.toDouble(),
      depthKm: _field<num?>(json, 'depth_km')?.toDouble(),
      region: _field<String?>(json, 'region'),
      latitudeText: _field<String?>(json, 'latitude_text'),
      longitudeText: _field<String?>(json, 'longitude_text'),
      potential: _field<String?>(json, 'potential'),
      felt: _field<String?>(json, 'felt'),
      shakemapUrl: _field<String?>(json, 'shakemap_url'),
    );
  }
}

class WeatherDetailDto {
  const WeatherDetailDto({
    required this.sender,
    required this.sent,
    required this.status,
    required this.msgType,
    required this.language,
    required this.capEvent,
    required this.eventCode,
    required this.headline,
    required this.description,
    required this.webUrl,
    required this.lifecycleComplete,
  });

  final String sender;
  final DateTime sent;
  final String status;
  final String msgType;
  final String? language;
  final String? capEvent;
  final String? eventCode;
  final String? headline;
  final String? description;
  final String? webUrl;
  final bool lifecycleComplete;

  factory WeatherDetailDto.fromJson(Map<String, dynamic> json) {
    return WeatherDetailDto(
      sender: _field<String>(json, 'sender'),
      sent: _date(json['sent']),
      status: _field<String>(json, 'status'),
      msgType: _field<String>(json, 'msg_type'),
      language: _field<String?>(json, 'language'),
      capEvent: _field<String?>(json, 'cap_event'),
      eventCode: _field<String?>(json, 'event_code'),
      headline: _field<String?>(json, 'headline'),
      description: _field<String?>(json, 'description'),
      webUrl: _field<String?>(json, 'web_url'),
      lifecycleComplete: _field<bool>(json, 'lifecycle_complete'),
    );
  }
}

class PolygonVertexDto {
  const PolygonVertexDto({
    required this.sequence,
    required this.latitude,
    required this.longitude,
  });

  final int sequence;
  final double latitude;
  final double longitude;

  factory PolygonVertexDto.fromJson(Map<String, dynamic> json) {
    return PolygonVertexDto(
      sequence: _field<int>(json, 'sequence'),
      latitude: _coordinate(json, 'latitude', 90) ?? (throw const FormatException('Missing latitude')),
      longitude: _coordinate(json, 'longitude', 180) ?? (throw const FormatException('Missing longitude')),
    );
  }
}

class AreaPolygonDto {
  const AreaPolygonDto({
    required this.id,
    required this.position,
    required this.geometryValid,
    required this.centroidLatitude,
    required this.centroidLongitude,
    required this.south,
    required this.north,
    required this.west,
    required this.east,
    required this.crossesAntimeridian,
    required this.vertices,
  });

  final String id;
  final int position;
  final bool geometryValid;
  final double? centroidLatitude;
  final double? centroidLongitude;
  final double? south;
  final double? north;
  final double? west;
  final double? east;
  final bool? crossesAntimeridian;
  final List<PolygonVertexDto> vertices;

  factory AreaPolygonDto.fromJson(Map<String, dynamic> json) {
    final result = AreaPolygonDto(
      id: _field<String>(json, 'id'),
      position: _field<int>(json, 'position'),
      geometryValid: _field<bool>(json, 'geometry_valid'),
      centroidLatitude: _coordinate(json, 'centroid_latitude', 90),
      centroidLongitude: _coordinate(json, 'centroid_longitude', 180),
      south: _coordinate(json, 'south', 90),
      north: _coordinate(json, 'north', 90),
      west: _coordinate(json, 'west', 180),
      east: _coordinate(json, 'east', 180),
      crossesAntimeridian: _field<bool?>(json, 'crosses_antimeridian'),
      vertices: _objects(json['vertices'], PolygonVertexDto.fromJson)
          ..sort((a, b) => a.sequence.compareTo(b.sequence)),
    );
    final bounds = [result.centroidLatitude, result.centroidLongitude, result.south,
      result.north, result.west, result.east, result.crossesAntimeridian];
    if (result.geometryValid
        ? bounds.contains(null) || result.vertices.length < 3 || result.south! > result.north!
        : bounds.any((value) => value != null)) {
      throw const FormatException('Invalid polygon geometry');
    }
    return result;
  }
}

class EventAreaDto {
  const EventAreaDto({
    required this.id,
    required this.position,
    required this.areaDescription,
    required this.polygons,
  });

  final String id;
  final int position;
  final String areaDescription;
  final List<AreaPolygonDto> polygons;

  factory EventAreaDto.fromJson(Map<String, dynamic> json) {
    return EventAreaDto(
      id: _field<String>(json, 'id'),
      position: _field<int>(json, 'position'),
      areaDescription: _field<String>(json, 'area_description'),
      polygons: _objects(json['polygons'], AreaPolygonDto.fromJson)
          ..sort((a, b) => a.position.compareTo(b.position)),
    );
  }
}

class EventReferenceDto {
  const EventReferenceDto({
    required this.relationType,
    required this.referencedSourceKey,
    required this.referencedEventId,
  });

  final String relationType;
  final String referencedSourceKey;
  final String? referencedEventId;

  factory EventReferenceDto.fromJson(Map<String, dynamic> json) {
    return EventReferenceDto(
      relationType: _field<String>(json, 'relation_type'),
      referencedSourceKey: _field<String>(json, 'referenced_source_key'),
      referencedEventId: _field<String?>(json, 'referenced_event_id'),
    );
  }
}

class EventDetailDto extends EventSummaryDto {
  EventDetailDto._(EventSummaryDto summary, {
    required this.sourceUrl, required this.firstSeenAt, required this.lastSeenAt,
    required this.earthquake, required this.weather, required this.areas, required this.references,
  }) : super(id: summary.id, source: summary.source, category: summary.category,
          title: summary.title, occurredAt: summary.occurredAt, latitude: summary.latitude,
          longitude: summary.longitude, isSimulated: summary.isSimulated,
          contentVersion: summary.contentVersion, lifecycleStatus: summary.lifecycleStatus,
          priority: summary.priority, cap: summary.cap);

  final String sourceUrl;
  final DateTime firstSeenAt;
  final DateTime lastSeenAt;
  final EarthquakeDetailDto? earthquake;
  final WeatherDetailDto? weather;
  final List<EventAreaDto> areas;
  final List<EventReferenceDto> references;

  factory EventDetailDto.fromJson(Map<String, dynamic> json) {
    try {
      final summary = EventSummaryDto.fromJson(json);
      final quake = _field<Map<String, dynamic>?>(json, 'earthquake');
      final weather = _field<Map<String, dynamic>?>(json, 'weather');
      final isQuake = summary.category == 'earthquake';
      if (isQuake != (quake != null) || isQuake == (weather != null)) {
        throw const FormatException('Invalid event category details');
      }
      return EventDetailDto._(summary,
        sourceUrl: _field<String>(json, 'source_url'),
        firstSeenAt: _date(json['first_seen_at']),
        lastSeenAt: _date(json['last_seen_at']),
        earthquake: quake == null ? null : EarthquakeDetailDto.fromJson(quake),
        weather: weather == null ? null : WeatherDetailDto.fromJson(weather),
        areas: _objects(json['areas'], EventAreaDto.fromJson)
            ..sort((a, b) => a.position.compareTo(b.position)),
        references: _objects(json['references'], EventReferenceDto.fromJson),
      );
    } on TypeError {
      throw const FormatException('Invalid event detail');
    }
  }
}

class EventDetailEnvelopeDto {
  const EventDetailEnvelopeDto(this.data, this.meta);
  final EventDetailDto data;
  final EventMetaDto meta;

  factory EventDetailEnvelopeDto.fromJson(Map<String, dynamic> json) {
    try {
      return EventDetailEnvelopeDto(
        EventDetailDto.fromJson(_field<Map<String, dynamic>>(json, 'data')),
        EventMetaDto.fromJson(_field<Map<String, dynamic>>(json, 'meta')),
      );
    } on TypeError {
      throw const FormatException('Invalid event metadata');
    }
  }
}
