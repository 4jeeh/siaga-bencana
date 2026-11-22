import 'dart:async';

import '../../core/network/api_client.dart';
import '../../core/network/sse_client.dart';
import 'notification_dto.dart';

class NotificationRepository {
  NotificationRepository(this.api);
  final ApiClient api;
  static const path = '/me/notifications';

  Future<NotificationHistoryFeedDto> history({int limit = 20, int offset = 0,
    bool unreadOnly = false}) async => NotificationHistoryFeedDto.fromJson(
    await api.getJson(path, authenticated: true, queryParameters: {
      'limit': '$limit', 'offset': '$offset', 'unread_only': '$unreadOnly',
    }));

  Future<NotificationReadDataDto> markRead(String notificationId) async =>
    NotificationReadDataDto.fromJson((await api.post(
      '$path/${Uri.encodeComponent(notificationId)}/read', {}, authenticated: true)).requiredData);

  Future<NotificationSyncFeedDto> baseline() => _sync({'baseline': 'true'});
  Future<NotificationSyncFeedDto> sync({required int sinceSequence,
    required String cursorUserId, int limit = 20}) => _sync({
      'since_sequence': '$sinceSequence', 'cursor_user_id': cursorUserId, 'limit': '$limit',
    });
  Completer<void>? _syncAbort;

  Future<NotificationSyncFeedDto> _sync(Map<String, String> query) async {
    final abort = _syncAbort = Completer<void>();
    try {
      return NotificationSyncFeedDto.fromJson(await api.getJson('$path/sync',
          authenticated: true, queryParameters: query, abortTrigger: abort.future));
    } finally {
      if (identical(_syncAbort, abort)) _syncAbort = null;
    }
  }

  Future<SseStreamHandle> openStream({required int sinceSequence,
    required String cursorUserId, String? lastEventId}) => api.openSse('$path/stream',
      queryParameters: {'since_sequence': '$sinceSequence', 'cursor_user_id': cursorUserId},
      headers: {'Last-Event-ID': ?lastEventId});

  void cancelStream() {
    final abort = _syncAbort;
    if (abort != null && !abort.isCompleted) abort.complete();
    _syncAbort = null;
    api.cancelSse();
  }
}
