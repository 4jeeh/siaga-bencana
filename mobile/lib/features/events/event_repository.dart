import '../../core/network/api_client.dart';
import 'event_dto.dart';

class EventRepository {
  EventRepository(this.api);
  final ApiClient api;

  Future<EventDetailEnvelopeDto> fetchEventDetail(String eventId) async {
    if (eventId.trim().isEmpty || eventId == '.' || eventId == '..' ||
        eventId.contains(RegExp(r'[/#?]'))) {
      throw ArgumentError.value(eventId, 'eventId');
    }
    final json = await api.getJson('/events/${Uri.encodeComponent(eventId)}', authenticated: true);
    return EventDetailEnvelopeDto.fromJson(json);
  }

  Future<EventFeedDto> fetchEvents({
    String? category,
    bool radiusOnly = true,
    String weatherStatus = 'active',
    String sort = 'recent',
    int limit = 20,
    int offset = 0,
  }) async {
    final json = await api.getJson('/events', authenticated: true, queryParameters: {
      'category': ?category,
      'radius_only': radiusOnly.toString(),
      'weather_status': weatherStatus,
      'sort': sort,
      'limit': limit.toString(),
      'offset': offset.toString(),
    });
    return EventFeedDto.fromJson(json);
  }
}
