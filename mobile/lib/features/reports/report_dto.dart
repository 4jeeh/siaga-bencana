import 'dart:math';

import '../../core/network/api_envelope.dart';
import '../events/event_dto.dart';

const reportCategories = {'earthquake': 'Gempa', 'flood': 'Banjir', 'eruption': 'Erupsi', 'extreme_weather': 'Cuaca Ekstrem', 'haze_other': 'Kabut Asap/Lainnya'};
const reportCategoryOrder = ['earthquake', 'flood', 'eruption', 'extreme_weather', 'haze_other'];
const reportStatusLabels = {'pending': 'Menunggu peninjauan', 'in_review': 'Sedang ditinjau', 'verified': 'Ditinjau admin', 'rejected': 'Ditolak'};
DateTime? _date(dynamic value) => value == null ? null : DateTime.parse(value as String).toUtc();

String generateUuidV4() {
  final random = Random.secure();
  final bytes = List.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final hex = bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0,8)}-${hex.substring(8,12)}-${hex.substring(12,16)}-${hex.substring(16,20)}-${hex.substring(20)}';
}

class ReportDto {
  const ReportDto({
    required this.id,
    required this.source,
    this.eventId,
    required this.category,
    required this.description,
    required this.latitude,
    required this.longitude,
    required this.status,
    this.verifiedAt,
    required this.hasPhoto,
    required this.isSimulated,
    required this.createdAt,
    this.matchDistanceKm,
    this.reporterId,
    this.reviewerId,
    this.version,
    this.clientRequestId,
    this.payloadHash,
    this.payloadHashAlgo,
    this.claimedAt,
    this.decidedAt,
    this.latestReason,
    this.updatedAt,
  });
  final String id;
  final String source;
  final String? eventId;
  final String category;
  final String description;
  final double latitude;
  final double longitude;
  final String status;
  final DateTime? verifiedAt;
  final bool hasPhoto;
  final bool isSimulated;
  final DateTime createdAt;
  final double? matchDistanceKm;
  final String? reporterId;
  final String? reviewerId;
  final int? version;
  final String? clientRequestId;
  final String? payloadHash;
  final String? payloadHashAlgo;
  final DateTime? claimedAt;
  final DateTime? decidedAt;
  final String? latestReason;
  final DateTime? updatedAt;
  factory ReportDto.fromJson(Map<String, dynamic> json) => ReportDto(
    id: json['id'] as String,
    source: json['source'] as String,
    eventId: json['event_id'] as String?,
    category: json['category'] as String,
    description: json['description'] as String,
    latitude: (json['latitude'] as num).toDouble(),
    longitude: (json['longitude'] as num).toDouble(),
    status: json['status'] as String,
    verifiedAt: _date(json['verified_at']),
    hasPhoto: json['has_photo'] as bool,
    isSimulated: json['is_simulated'] as bool,
    createdAt: DateTime.parse(json['created_at'] as String).toUtc(),
    matchDistanceKm: (json['match_distance_km'] as num?)?.toDouble(),
    reporterId: json['reporter_id'] as String?,
    reviewerId: json['reviewer_id'] as String?,
    version: json['version'] as int?,
    clientRequestId: json['client_request_id'] as String?,
    payloadHash: json['payload_hash'] as String?,
    payloadHashAlgo: json['payload_hash_algo'] as String?,
    claimedAt: _date(json['claimed_at']),
    decidedAt: _date(json['decided_at']),
    latestReason: json['latest_reason'] as String?,
    updatedAt: _date(json['updated_at']),
  );
  bool get isPrivate => reporterId != null && version != null;
}

class ReportFeedMetaDto extends ApiMeta {
  const ReportFeedMetaDto({required super.serverTime, required super.mode, required super.isSimulated, this.zoneVersion});
  final int? zoneVersion;
  factory ReportFeedMetaDto.fromJson(Map<String, dynamic> json) {
    final meta = ApiMeta.fromJson(json);
    return ReportFeedMetaDto(serverTime: meta.serverTime, mode: meta.mode, isSimulated: meta.isSimulated, zoneVersion: json['zone_version'] as int?);
  }
}

class ReportEnvelopeDto {
  const ReportEnvelopeDto(this.data, this.meta, {this.idempotentReplay = false});
  final ReportDto data;
  final ApiMeta meta;
  final bool idempotentReplay;
  factory ReportEnvelopeDto.fromJson(Map<String, dynamic> json) {
    final envelope = ApiEnvelope.fromJson(json);
    return ReportEnvelopeDto(ReportDto.fromJson(envelope.requiredData), envelope.meta);
  }
}

class ReportFeedDto {
  const ReportFeedDto(this.items, this.page, this.meta);
  final List<ReportDto> items;
  final PageDto page;
  final ReportFeedMetaDto meta;
  factory ReportFeedDto.fromJson(Map<String, dynamic> json) => ReportFeedDto(
    (json['items'] as List<dynamic>).cast<Map<String, dynamic>>().map(ReportDto.fromJson).toList(),
    PageDto.fromJson(json['page'] as Map<String, dynamic>),
    ReportFeedMetaDto.fromJson(json['meta'] as Map<String, dynamic>),
  );
}
class PhotoUrlDto {
  const PhotoUrlDto({
    required this.url,
    required this.expiresAt,
    required this.expiresIn,
    required this.contentType,
    required this.isSimulated,
  });
  final String url;
  final DateTime expiresAt;
  final int expiresIn;
  final String contentType;
  final bool isSimulated;
  factory PhotoUrlDto.fromJson(Map<String, dynamic> json) => PhotoUrlDto(
    url: json['url'] as String,
    expiresAt: DateTime.parse(json['expires_at'] as String).toUtc(),
    expiresIn: json['expires_in'] as int,
    contentType: json['content_type'] as String,
    isSimulated: json['is_simulated'] as bool,
  );
}
class ModerationResultDto {
  const ModerationResultDto({
    required this.id,
    required this.status,
    this.reviewerId,
    required this.version,
    this.claimedAt,
    this.decidedAt,
  });
  final String id;
  final String status;
  final String? reviewerId;
  final int version;
  final DateTime? claimedAt;
  final DateTime? decidedAt;
  factory ModerationResultDto.fromJson(Map<String, dynamic> json) => ModerationResultDto(
    id: json['id'] as String,
    status: json['status'] as String,
    reviewerId: json['reviewer_id'] as String?,
    version: json['version'] as int,
    claimedAt: _date(json['claimed_at']),
    decidedAt: _date(json['decided_at']),
  );
}
class VerificationDto {
  const VerificationDto({
    required this.id,
    required this.reportId,
    required this.moderatorId,
    required this.fromStatus,
    required this.toStatus,
    this.reason,
    required this.resultingVersion,
    required this.createdAt,
  });
  final String id;
  final String reportId;
  final String moderatorId;
  final String fromStatus;
  final String toStatus;
  final String? reason;
  final int resultingVersion;
  final DateTime createdAt;
  factory VerificationDto.fromJson(Map<String, dynamic> json) => VerificationDto(
    id: json['id'] as String,
    reportId: json['report_id'] as String,
    moderatorId: json['moderator_id'] as String,
    fromStatus: json['from_status'] as String,
    toStatus: json['to_status'] as String,
    reason: json['reason'] as String?,
    resultingVersion: json['resulting_version'] as int,
    createdAt: DateTime.parse(json['created_at'] as String).toUtc(),
  );
}
class VerificationFeedDto {
  const VerificationFeedDto(this.items, this.page, this.meta);
  final List<VerificationDto> items;
  final PageDto page;
  final ApiMeta meta;
  factory VerificationFeedDto.fromJson(Map<String, dynamic> json) => VerificationFeedDto(
    (json['items'] as List<dynamic>).cast<Map<String, dynamic>>().map(VerificationDto.fromJson).toList(),
    PageDto.fromJson(json['page'] as Map<String, dynamic>),
    ApiMeta.fromJson(json['meta'] as Map<String, dynamic>),
  );
}
