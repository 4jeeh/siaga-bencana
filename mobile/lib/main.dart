import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'app.dart';
import 'core/config/api_config.dart';

import 'core/session/session_store.dart';

void main() {
  runApp(SiagaApp(client: http.Client(), baseUrl: ApiConfig.baseUrl, sessionStore: SecureSessionStore()));
}
