import '../../core/network/api_client.dart';
import 'zone_dto.dart';

class ZoneRepository {
  ZoneRepository(this.api);
  final ApiClient api;

  Future<ZoneDto?> fetchZone() async {
    final response = await api.get('/me/zone', authenticated: true);
    return response.data == null ? null : ZoneDto.fromJson(response.requiredData);
  }

  Future<ZoneDto> saveZone(ZoneUpdateRequest request) async => ZoneDto.fromJson(
    (await api.put('/me/zone', request.toJson(), authenticated: true)).requiredData,
  );
}
