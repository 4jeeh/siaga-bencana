class CurrentWeatherDto {
  const CurrentWeatherDto({required this.temperatureC, required this.humidityPercent,
    required this.precipitationMm, required this.windSpeedKmh, required this.weatherCode,
    required this.conditionCode, required this.conditionLabel, required this.observedAt,
    required this.source, required this.isCached});

  final double temperatureC, humidityPercent, precipitationMm, windSpeedKmh;
  final int weatherCode;
  final String conditionCode, conditionLabel, source;
  final DateTime observedAt;
  final bool isCached;

  factory CurrentWeatherDto.fromJson(Map<String, dynamic> json) {
    double number(String key) {
      final value = json[key];
      if (value is num && value.isFinite) return value.toDouble();
      throw FormatException('Invalid $key');
    }

    if (json case {'weather_code': int code, 'condition_code': String condition,
        'condition_label': String label, 'observed_at': String observed,
        'source': String source, 'is_cached': bool cached}) {
      return CurrentWeatherDto(temperatureC: number('temperature_c'),
        humidityPercent: number('humidity_percent'), precipitationMm: number('precipitation_mm'),
        windSpeedKmh: number('wind_speed_kmh'), weatherCode: code, conditionCode: condition,
        conditionLabel: label, observedAt: DateTime.parse(observed).toUtc(), source: source,
        isCached: cached);
    }
    throw const FormatException('Respons cuaca tidak valid.');
  }
}
