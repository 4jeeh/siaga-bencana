import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../session/session_coordinator.dart';
import 'api_envelope.dart';

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
  }) => _sendJson('GET', path, queryParameters: queryParameters, authenticated: authenticated);

  Future<Map<String, dynamic>> _sendJson(
    String method,
    String path, {
    Map<String, String>? queryParameters,
    http.MultipartRequest Function(Uri)? multipart,
    void Function(http.Response)? onResponse,
    Map<String, dynamic>? data,
    bool authenticated = false,
  }) async {
    if (!path.startsWith('/') || path.contains('://') || path.contains('?') || path.contains('#')) {
      throw ArgumentError('Only relative API paths are allowed');
    }
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
    final endpoint = Uri.parse(
      '${baseUrl.toString().replaceFirst(RegExp(r'/$'), '')}$path',
    );
    final uri = endpoint.replace(queryParameters: queryParameters);
    var statusCode = 0;
    try {
      final request = (multipart?.call(uri) ?? http.Request(method, uri))
        ..headers.addAll(headers)
        ..followRedirects = false;
      if (data != null) (request as http.Request).body = jsonEncode(data);
      final response = await client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(Duration(seconds: multipart == null ? 15 : 25));
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

  void close() => client.close();
}
