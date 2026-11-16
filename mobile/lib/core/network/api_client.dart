import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../session/session_coordinator.dart';
import 'api_envelope.dart';

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
  Future<ApiEnvelope> post(String path, Map<String, dynamic> data) =>
      _request('POST', path, data: data);
  Future<ApiEnvelope> _request(
    String method,
    String path, {
    Map<String, dynamic>? data,
    bool authenticated = false,
  }) async {
    if (!path.startsWith('/') || path.contains('://') || path.contains('?')) {
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
    final uri = Uri.parse(
      '${baseUrl.toString().replaceFirst(RegExp(r'/$'), '')}$path',
    );
    try {
      final request = http.Request(method, uri)
        ..headers.addAll(headers)
        ..followRedirects = false;
      if (data != null) request.body = jsonEncode(data);
      final response = await client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(const Duration(seconds: 15));
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
      return ApiEnvelope.fromJson(json);
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
      throw const ApiErrorEnvelope(
        code: 'INVALID_RESPONSE',
        message: 'Respons API tidak valid.',
      );
    } on TypeError {
      throw const ApiErrorEnvelope(
        code: 'INVALID_RESPONSE',
        message: 'Respons API tidak valid.',
      );
    }
  }

  void close() => client.close();
}
