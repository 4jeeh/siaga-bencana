import 'dart:typed_data';

import '../../core/network/api_client.dart';
import 'report_dto.dart';
import 'report_text.dart';

class ReportRepository {
  ReportRepository(this.api);
  final ApiClient api;

  String _path(String id) {
    if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(id)) throw ArgumentError.value(id, 'reportId');
    return '/reports/$id';
  }

  Future<ReportFeedDto> fetchReports({required String scope, String? category, String? status, String? eventId, int limit = 20, int offset = 0}) async =>
      ReportFeedDto.fromJson(await api.getJson('/reports', authenticated: true, queryParameters: {
        'scope': scope, 'category': ?category, 'status': ?status,
        'event_id': ?eventId, 'limit': '$limit', 'offset': '$offset',
      }));

  Future<ReportEnvelopeDto> fetchReportDetail(String id) async {
    final result = await api.get(_path(id), authenticated: true);
    final report = ReportDto.fromJson(result.requiredData);
    if (report.id != id) throw const FormatException('ID laporan tidak sesuai.');
    return ReportEnvelopeDto(report, result.meta);
  }

  Future<VerificationFeedDto> fetchVerifications(String id, {int limit = 20, int offset = 0}) async => VerificationFeedDto.fromJson(
    await api.getJson('${_path(id)}/verifications', authenticated: true, queryParameters: {'limit': '$limit', 'offset': '$offset'}));

  Future<PhotoUrlDto> fetchPhotoUrl(String id) async => PhotoUrlDto.fromJson((await api.get('${_path(id)}/photo-url', authenticated: true)).requiredData);

  Future<ReportEnvelopeDto> submitReport({required String clientRequestId, required String category, required String description,
    required double latitude, required double longitude, String? eventId, Uint8List? photo}) async {
    final result = await api.postMultipart('/reports', fields: {'client_request_id': clientRequestId, 'category': category,
      'description': normalizeReportText(description), 'latitude': '$latitude', 'longitude': '$longitude',
      'event_id': ?eventId}, fileBytes: photo);
    return ReportEnvelopeDto(ReportDto.fromJson(result.envelope.requiredData), result.envelope.meta, idempotentReplay: result.idempotentReplay);
  }

  Future<ModerationResultDto> claimReport(String id, int expectedVersion) async => ModerationResultDto.fromJson((await api.post(
    '${_path(id)}/claim', {'expected_version': expectedVersion}, authenticated: true)).requiredData);

  Future<ModerationResultDto> decideReport(String id, int expectedVersion, String outcome, String reason) async => ModerationResultDto.fromJson((await api.post(
    '${_path(id)}/decision', {'expected_version': expectedVersion, 'outcome': outcome, 'reason': reason.trim()}, authenticated: true)).requiredData);
}
