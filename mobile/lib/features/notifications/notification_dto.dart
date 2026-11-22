import '../../core/network/api_envelope.dart';
import '../events/event_dto.dart';

String _choice(Map<String, dynamic> json, String key, Set<String> values) {
  final value = json[key];
  if (value is String && values.contains(value)) return value;
  throw FormatException('Nilai $key tidak valid.');
}

T? _nullable<T>(Map<String, dynamic> json, String key) {
  if (!json.containsKey(key)) throw FormatException('Kolom $key tidak tersedia.');
  return json[key] as T?;
}

class NotificationDto {
  const NotificationDto({
    required this.id,
    required this.eventId,
    required this.kind,
    required this.sequence,
    required this.zoneVersion,
    required this.priorityAlgo,
    required this.priorityScore,
    required this.priorityLabel,
    required this.priorityReasons,
    required this.priorityComponents,
    required this.matchMethod,
    required this.matchDistanceKm,
    required this.evaluatedAt,
    required this.createdAt,
    required this.readAt,
    required this.isSimulated,
    required this.title,
    required this.eventCategory,
    required this.currentLifecycleStatus,
    required this.presentAsActiveAlert,
  });

  final String id;
  final String eventId;
  final String kind;
  final int sequence;
  final int zoneVersion;
  final String priorityAlgo;
  final double? priorityScore;
  final String priorityLabel;
  final List<PriorityReasonDto> priorityReasons;
  final Map<String, double>? priorityComponents;
  final String matchMethod;
  final double matchDistanceKm;
  final DateTime evaluatedAt;
  final DateTime createdAt;
  final DateTime? readAt;
  final bool isSimulated;
  final String title;
  final String eventCategory;
  final String currentLifecycleStatus;
  final bool presentAsActiveAlert;

  factory NotificationDto.fromJson(Map<String, dynamic> json) => NotificationDto(
    id: json['id'] as String,
    eventId: json['event_id'] as String,
    kind: _choice(json, 'kind', const {'official_new'}),
    sequence: json['sequence'] as int,
    zoneVersion: json['zone_version'] as int,
    priorityAlgo: _choice(json, 'priority_algo', const {'eq-priority-v1', 'cap-priority-v1'}),
    priorityScore: _nullable<num>(json, 'priority_score')?.toDouble(),
    priorityLabel: _choice(json, 'priority_label', const {'ordinary', 'attention', 'high', 'information', 'unavailable'}),
    priorityReasons: (json['priority_reasons'] as List<dynamic>).cast<Map<String, dynamic>>().map(PriorityReasonDto.fromJson).toList(),
    priorityComponents: _nullable<Map<String, dynamic>>(json, 'priority_components')?.map((key, value) => MapEntry(key, (value as num).toDouble())),
    matchMethod: _choice(json, 'match_method', const {'point_distance', 'inside_polygon', 'near_polygon_sample'}),
    matchDistanceKm: (json['match_distance_km'] as num).toDouble(),
    evaluatedAt: DateTime.parse(json['evaluated_at'] as String).toUtc(),
    createdAt: DateTime.parse(json['created_at'] as String).toUtc(),
    readAt: _nullable<String>(json, 'read_at') == null ? null : DateTime.parse(json['read_at'] as String).toUtc(),
    isSimulated: json['is_simulated'] as bool,
    title: json['title'] as String,
    eventCategory: _choice(json, 'event_category', const {'earthquake', 'extreme_weather'}),
    currentLifecycleStatus: json['current_lifecycle_status'] as String,
    presentAsActiveAlert: json['present_as_active_alert'] as bool,
  );

  NotificationDto copyWithReadAt(DateTime value) => NotificationDto(
    id: id,
    eventId: eventId,
    kind: kind,
    sequence: sequence,
    zoneVersion: zoneVersion,
    priorityAlgo: priorityAlgo,
    priorityScore: priorityScore,
    priorityLabel: priorityLabel,
    priorityReasons: priorityReasons,
    priorityComponents: priorityComponents,
    matchMethod: matchMethod,
    matchDistanceKm: matchDistanceKm,
    evaluatedAt: evaluatedAt,
    createdAt: createdAt,
    readAt: value,
    isSimulated: isSimulated,
    title: title,
    eventCategory: eventCategory,
    currentLifecycleStatus: currentLifecycleStatus,
    presentAsActiveAlert: presentAsActiveAlert,
  );
}

class NotificationHistoryFeedDto {
  const NotificationHistoryFeedDto({
    required this.items,
    required this.page,
    required this.unreadCount,
    required this.meta,
  });

  final List<NotificationDto> items;
  final PageDto page;
  final int unreadCount;
  final ApiMeta meta;

  factory NotificationHistoryFeedDto.fromJson(Map<String, dynamic> json) => NotificationHistoryFeedDto(
    items: (json['items'] as List<dynamic>).cast<Map<String, dynamic>>().map(NotificationDto.fromJson).toList(),
    page: PageDto.fromJson(json['page'] as Map<String, dynamic>),
    unreadCount: json['unread_count'] as int,
    meta: ApiMeta.fromJson(json['meta'] as Map<String, dynamic>),
  );
}

class NotificationSyncFeedDto {
  const NotificationSyncFeedDto({
    required this.items,
    required this.cursorUserId,
    required this.highWaterMark,
    required this.nextSequence,
    required this.hasMore,
    required this.meta,
  });

  final List<NotificationDto> items;
  final String cursorUserId;
  final int highWaterMark;
  final int nextSequence;
  final bool hasMore;
  final ApiMeta meta;

  factory NotificationSyncFeedDto.fromJson(Map<String, dynamic> json) => NotificationSyncFeedDto(
    items: (json['items'] as List<dynamic>).cast<Map<String, dynamic>>().map(NotificationDto.fromJson).toList(),
    cursorUserId: json['cursor_user_id'] as String,
    highWaterMark: json['high_water_mark'] as int,
    nextSequence: json['next_sequence'] as int,
    hasMore: json['has_more'] as bool,
    meta: ApiMeta.fromJson(json['meta'] as Map<String, dynamic>),
  );
}

class NotificationReadDataDto {
  const NotificationReadDataDto({
    required this.id,
    required this.readAt,
  });

  final String id;
  final DateTime readAt;

  factory NotificationReadDataDto.fromJson(Map<String, dynamic> json) => NotificationReadDataDto(
    id: json['id'] as String,
    readAt: DateTime.parse(json['read_at'] as String).toUtc(),
  );
}

class SseConnectedPayload {
  const SseConnectedPayload({
    required this.cursorUserId,
    required this.sinceSequence,
    required this.highWaterMark,
    required this.heartbeatSeconds,
    required this.isSimulated,
  });

  final String cursorUserId;
  final int sinceSequence;
  final int highWaterMark;
  final int heartbeatSeconds;
  final bool isSimulated;

  factory SseConnectedPayload.fromJson(Map<String, dynamic> json) => SseConnectedPayload(
    cursorUserId: json['cursor_user_id'] as String,
    sinceSequence: json['since_sequence'] as int,
    highWaterMark: json['high_water_mark'] as int,
    heartbeatSeconds: json['heartbeat_seconds'] as int,
    isSimulated: json['is_simulated'] as bool,
  );
}
