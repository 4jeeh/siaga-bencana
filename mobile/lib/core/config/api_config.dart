import 'package:flutter/foundation.dart';

abstract final class ApiConfig {
  static Uri get baseUrl {
    const override = String.fromEnvironment('API_BASE_URL');
    final fallback = !kIsWeb && defaultTargetPlatform == TargetPlatform.android
        ? 'http://10.0.2.2:8000/api/v1'
        : 'http://127.0.0.1:8000/api/v1';
    final uri = Uri.parse(override.isEmpty ? fallback : override);
    if (!uri.hasAuthority ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        !['http', 'https'].contains(uri.scheme) ||
        (kReleaseMode && uri.scheme != 'https')) {
      throw ArgumentError(
        'API_BASE_URL must be an API URL; release requires HTTPS.',
      );
    }
    return uri;
  }
}
