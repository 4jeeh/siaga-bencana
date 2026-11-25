import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../session/session_coordinator.dart';
import 'api_envelope.dart';
import 'sse_client.dart';

class MultipartApiEnvelope {
  const MultipartApiEnvelope(this.envelope, this.idempotentReplay);
  final ApiEnvelope envelope;
  final bool idempotentReplay;
}

class ApiClient {
  ApiClient({
    required this.client,
    required this.baseUrl,
    required this.session,
  });
  final http.Client client;
  final Uri baseUrl;
  final SessionCoordinator session;
  Future<ApiEnvelope> get(String path, {bool authenticated = false}) =>
      _request('GET', path, authenticated: authenticated);
  Future<ApiEnvelope> post(String path, Map<String, dynamic> data, {bool authenticated = false}) =>
      _request('POST', path, data: data, authenticated: authenticated);

  Future<MultipartApiEnvelope> postMultipart(String path, {
    required Map<String, String> fields, Uint8List? fileBytes, String fileField = 'photo',
    String filename = 'report.jpg', MediaType? contentType, bool authenticated = true,
  }) async {
    var replay = false;
    final json = await _sendJson('POST', path, authenticated: authenticated,
      multipart: (uri) => http.MultipartRequest('POST', uri)
        ..fields.addAll(fields)
        ..files.addAll([if (fileBytes != null) http.MultipartFile.fromBytes(fileField, fileBytes,
          filename: filename, contentType: contentType ?? MediaType('image', 'jpeg'))]),
      onResponse: (response) => replay = response.headers.entries.any(
        (header) => header.key.toLowerCase() == 'idempotent-replay' && header.value.trim() == 'true',
      ));
    return MultipartApiEnvelope(_envelope(json), replay);
  }
  Future<ApiEnvelope> put(
    String path,
    Map<String, dynamic> data, {
    bool authenticated = true,
  }) => _request('PUT', path, data: data, authenticated: authenticated);
  Future<ApiEnvelope> _request(
    String method,
    String path, {
    Map<String, dynamic>? data,
    bool authenticated = false,
  }) async {
    final json = await _sendJson(method, path, data: data, authenticated: authenticated);
    return _envelope(json);
  }

  ApiEnvelope _envelope(Map<String, dynamic> json) {
    try {
      return ApiEnvelope.fromJson(json);
    } on FormatException {
      throw const ApiErrorEnvelope(code: 'INVALID_RESPONSE', message: 'Respons API tidak valid.');
    } on TypeError {
      throw const ApiErrorEnvelope(code: 'INVALID_RESPONSE', message: 'Respons API tidak valid.');
    }
  }

  Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, String>? queryParameters,
    bool authenticated = false,
    Future<void>? abortTrigger,
  }) => _sendJson('GET', path, queryParameters: queryParameters, authenticated: authenticated,
    abortTrigger: abortTrigger);

  Future<Map<String, dynamic>> _sendJson(
    String method,
    String path, {
    Map<String, String>? queryParameters,
    Future<void>? abortTrigger,
    http.MultipartRequest Function(Uri)? multipart,
    void Function(http.Response)? onResponse,
    Map<String, dynamic>? data,
    bool authenticated = false,
  }) async {
    final uri = _uri(path, queryParameters);
    session.checkExpiry();
    final token = session.token;
    final generation = session.generation;
    if (authenticated && token == null) {
      throw const ApiErrorEnvelope(
        code: 'AUTH_REQUIRED',
        message: 'Silakan masuk terlebih dahulu.',
      );
    }
    final headers = {
      'Accept': 'application/json',
      if (data != null) 'Content-Type': 'application/json; charset=utf-8',
      if (authenticated) 'Authorization': 'Bearer $token',
    };
    var aborted = false;
    unawaited(abortTrigger?.then<void>((_) { aborted = true; },
        onError: (Object _) { aborted = true; }));
    Future<http.Response> send() async {
      final request = (multipart?.call(uri) ?? http.AbortableRequest(method, uri, abortTrigger: abortTrigger))
        ..headers.addAll(headers)
        ..followRedirects = false;
      if (data != null) (request as http.Request).body = jsonEncode(data);
      final pending = client.send(request).then(http.Response.fromStream);
      return _untilCancelled(pending, abortTrigger)
          .timeout(Duration(seconds: multipart == null ? 15 : 25));
    }

    var statusCode = 0;
    try {
      final maxAttempts = method == 'GET' ? 2 : 1;
      late http.Response response;
      for (var attempt = 1; ; attempt++) {
        try {
          response = await send();
          break;
        } on http.ClientException {
          if (aborted) {
            throw const ApiErrorEnvelope(code: 'CANCELLED', message: 'Permintaan dibatalkan.');
          }
          if (attempt >= maxAttempts || (authenticated && generation != session.generation)) rethrow;
        }
      }
      statusCode = response.statusCode;
      if (authenticated && generation != session.generation) {
        throw const ApiErrorEnvelope(
          code: 'SESSION_CHANGED',
          message: 'Sesi telah berubah.',
        );
      }
      if (authenticated && response.statusCode == 401) {
        session.clear(expired: true);
      }
      final json =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ApiErrorEnvelope.fromJson(
          json,
          statusCode: response.statusCode,
          retryAfter: int.tryParse(response.headers['retry-after'] ?? ''),
        );
      }
      onResponse?.call(response);
      return json;
    } on ApiErrorEnvelope {
      rethrow;
    } on TimeoutException {
      throw const ApiErrorEnvelope(
        code: 'NETWORK_ERROR',
        message: 'Koneksi terlalu lama. Coba lagi.',
      );
    } on http.ClientException {
      throw const ApiErrorEnvelope(
        code: 'NETWORK_ERROR',
        message: 'API tidak terjangkau. Coba lagi.',
      );
    } on FormatException {
      throw ApiErrorEnvelope(
        statusCode: statusCode,
        code: 'INVALID_RESPONSE',
        message: 'Respons API tidak valid.',
      );
    } on TypeError {
      throw ApiErrorEnvelope(
        statusCode: statusCode,
        code: 'INVALID_RESPONSE',
        message: 'Respons API tidak valid.',
      );
    }
  }

  Uri _uri(String path, Map<String, String>? queryParameters) {
    if (!path.startsWith('/') || path.startsWith('//') || path.contains('://') || path.contains('?') || path.contains('#')) {
      throw ArgumentError('Only relative API paths are allowed');
    }
    final endpoint = Uri.parse(
      '${baseUrl.toString().replaceFirst(RegExp(r'/$'), '')}$path',
    );
    return endpoint.replace(queryParameters: queryParameters);
  }

  Future<T> _untilCancelled<T>(Future<T> pending, Future<void>? abort) {
    if (abort == null) return pending;
    return Future.any<T>([pending, abort.then<T>((_) =>
        throw const ApiErrorEnvelope(code: 'CANCELLED', message: 'Permintaan dibatalkan.'))]);
  }

  Completer<void>? _sseAbort;

  void cancelSse() {
    final abort = _sseAbort;
    if (abort != null && !abort.isCompleted) abort.complete();
    _sseAbort = null;
  }

  Future<SseStreamHandle> openSse(String path, {
    Map<String, String>? queryParameters, Map<String, String>? headers,
  }) async {
    final uri = _uri(path, queryParameters);
    session.checkExpiry();
    final token = session.token;
    final generation = session.generation;
    if (token == null) {
      throw const ApiErrorEnvelope(code: 'AUTH_REQUIRED', message: 'Silakan masuk terlebih dahulu.');
    }
    cancelSse();
    final abort = _sseAbort = Completer<void>();
    void stop() {
      if (!abort.isCompleted) abort.complete();
      if (identical(_sseAbort, abort)) _sseAbort = null;
    }
    final request = http.AbortableRequest('GET', uri, abortTrigger: abort.future)
      ..followRedirects = false
      ..headers.addAll({...?headers, 'Authorization': 'Bearer $token', 'Accept': 'text/event-stream'});
    var handedOff = false;
    try {
      final pending = client.send(request).then((response) async {
        if (abort.isCompleted) {
          await response.stream.listen(null).cancel();
          throw const ApiErrorEnvelope(code: 'CANCELLED', message: 'Permintaan dibatalkan.');
        }
        return response;
      });
      final response = await _untilCancelled(pending, abort.future).timeout(const Duration(seconds: 15));
      if (abort.isCompleted || generation != session.generation) {
        await response.stream.listen(null).cancel();
        throw const ApiErrorEnvelope(code: 'SESSION_CHANGED', message: 'Sesi telah berubah.');
      }
      if (response.statusCode != 200) {
        try {
          final body = await _untilCancelled(response.stream.bytesToString(), abort.future)
              .timeout(const Duration(seconds: 15));
          throw ApiErrorEnvelope.fromJson(jsonDecode(body) as Map<String, dynamic>,
            statusCode: response.statusCode, retryAfter: int.tryParse(response.headers['retry-after'] ?? ''));
        } on FormatException {
          throw _invalidStreamResponse(response);
        } on TypeError {
          throw _invalidStreamResponse(response);
        } finally {
          if (response.statusCode == 401 && session.generation == generation && !abort.isCompleted) {
            session.clear(expired: true);
          }
        }
      }
      handedOff = true;
      return SseStreamHandle(response.stream, stop);
    } on TimeoutException {
      throw const ApiErrorEnvelope(code: 'NETWORK_ERROR', message: 'Koneksi terlalu lama. Coba lagi.');
    } on http.ClientException {
      throw const ApiErrorEnvelope(code: 'NETWORK_ERROR', message: 'API tidak terjangkau. Coba lagi.');
    } finally {
      if (!handedOff) stop();
    }
  }

  ApiErrorEnvelope _invalidStreamResponse(http.StreamedResponse response) => ApiErrorEnvelope(
    statusCode: response.statusCode, code: 'INVALID_RESPONSE',
    message: 'Respons kanal notifikasi tidak valid.',
    retryAfter: int.tryParse(response.headers['retry-after'] ?? ''),
  );

  void close() {
    cancelSse();
    client.close();
  }
}
