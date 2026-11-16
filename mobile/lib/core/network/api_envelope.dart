class ApiMeta {
  const ApiMeta({
    required this.serverTime,
    required this.mode,
    required this.isSimulated,
  });
  final DateTime serverTime;
  final String mode;
  final bool isSimulated;
  factory ApiMeta.fromJson(Map<String, dynamic> json) {
    final mode = json['mode'] as String;
    final simulated = json['is_simulated'] as bool;
    if (!['local_live', 'production_live', 'simulation'].contains(mode) ||
        simulated != (mode == 'simulation')) {
      throw const FormatException('Invalid API mode');
    }
    return ApiMeta(
      serverTime: DateTime.parse(json['server_time'] as String).toUtc(),
      mode: mode,
      isSimulated: simulated,
    );
  }
}

class ApiErrorEnvelope implements Exception {
  const ApiErrorEnvelope({
    required this.code,
    required this.message,
    this.details,
    this.requestId,
    this.statusCode = 0,
    this.retryAfter,
  });
  final String code;
  final String message;
  final Map<String, dynamic>? details;
  final String? requestId;
  final int statusCode;
  final int? retryAfter;
  factory ApiErrorEnvelope.fromJson(
    Map<String, dynamic> json, {
    int statusCode = 0,
    int? retryAfter,
  }) => ApiErrorEnvelope(
    code: json['code'] as String,
    message: json['message'] as String,
    details: json['details'] as Map<String, dynamic>?,
    requestId: json['request_id'] as String,
    statusCode: statusCode,
    retryAfter: retryAfter,
  );
  Map<String, dynamic> toJson() => {
    'code': code,
    'message': message,
    'details': details,
    'request_id': requestId,
  };
  @override
  String toString() => '$code: $message';
}

class ApiEnvelope {
  const ApiEnvelope(this.data, this.meta);
  final Map<String, dynamic> data;
  final ApiMeta meta;
  factory ApiEnvelope.fromJson(Map<String, dynamic> json) => ApiEnvelope(
    json['data'] as Map<String, dynamic>,
    ApiMeta.fromJson(json['meta'] as Map<String, dynamic>),
  );
}
