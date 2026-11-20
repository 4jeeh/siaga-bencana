import '../../core/network/api_client.dart';
import 'map_dto.dart';

class MapRepository {
  MapRepository(this.api);
  final ApiClient api;

  Future<MarkerFeedDto> fetchMarkers({
    String? bbox, String? category, bool radiusOnly = true, bool includeReports = true,
  }) async {
    final json = await api.getJson('/map/markers', authenticated: true, queryParameters: {
      'bbox': ?bbox, 'category': ?category,
      'radius_only': radiusOnly.toString(), 'include_reports': includeReports.toString(),
    });
    return MarkerFeedDto.fromJson(json);
  }
}
