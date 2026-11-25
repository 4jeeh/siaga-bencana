import '../../core/network/api_client.dart';
import 'zone_dto.dart';

class ZoneRepository {
  ZoneRepository(this.api);
  final ApiClient api;

  Future<List<LocationSuggestionDto>> searchLocations(String query, {int limit = 6}) async {
    final response = await api.getJson('/locations/search', authenticated: true,
      queryParameters: {'q': query.trim(), 'limit': '$limit'});
    final items = switch (response) {
      {'items': List<dynamic> items} => items,
      {'data': List<dynamic> items} => items,
      {'data': {'items': List<dynamic> items}} => items,
      _ => throw const FormatException('Daftar wilayah tidak valid.'),
    };
    return items.map((item) {
      if (item is! Map<String, dynamic>) throw const FormatException('Wilayah tidak valid.');
      return LocationSuggestionDto.fromJson(item);
    }).toList(growable: false);
  }

  Future<ZoneDto?> fetchZone() async {
    final response = await api.get('/me/zone', authenticated: true);
    return response.data == null ? null : ZoneDto.fromJson(response.requiredData);
  }

  Future<ZoneDto> saveZone(ZoneUpdateRequest request) async => ZoneDto.fromJson(
    (await api.put('/me/zone', request.toJson(), authenticated: true)).requiredData,
  );
}
