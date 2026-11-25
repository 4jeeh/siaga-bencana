import '../../core/network/api_client.dart';
import 'weather_dto.dart';

class WeatherRepository {
  WeatherRepository(this.api);
  final ApiClient api;

  Future<CurrentWeatherDto?> fetchCurrentWeather() async {
    final response = await api.get('/me/weather', authenticated: true);
    return response.data == null ? null : CurrentWeatherDto.fromJson(response.requiredData);
  }
}
