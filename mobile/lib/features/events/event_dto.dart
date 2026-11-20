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

DateTime _date(dynamic value) => DateTime.parse(value as String).toUtc();
DateTime? _optionalDate(dynamic value) => value == null ? null : _date(value);

List<T> _objects<T>(dynamic value, T Function(Map<String, dynamic>) decode) =>
    (value as List<dynamic>).cast<Map<String, dynamic>>().map(decode).toList(growable: false);

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
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
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
