import httpx

from app.schemas.weather import CurrentWeatherDTO
from app.services.ttl_cache import TTLCache


def condition(code):
    match code:
        case 0:
            return "clear", "Cerah"
        case 1 | 2:
            return "partly_cloudy", "Cerah berawan"
        case 3:
            return "cloudy", "Berawan"
        case 45 | 48:
            return "fog", "Berkabut"
        case 51 | 53 | 55 | 56 | 57:
            return "drizzle", "Gerimis"
        case 61 | 63 | 66 | 80 | 81:
            return "rain", "Hujan"
        case 65 | 67 | 82:
            return "heavy_rain", "Hujan lebat"
        case 95 | 96 | 99:
            return "thunderstorm", "Hujan petir"
        case _:
            return "unknown", "Cuaca bervariasi"


class WeatherService:
    def __init__(self):
        self.cache = TTLCache[tuple[float, float], CurrentWeatherDTO](600)

    def current(self, zone, settings):
        if settings.app_mode == "simulation":
            return None
        key = (round(zone.latitude, 2), round(zone.longitude, 2))
        cached = self.cache.get(key)
        if cached is not None:
            return cached.model_copy(update={"is_cached": True})
        try:
            response = httpx.get(
                "https://api.open-meteo.com/v1/forecast",
                params={
                    "latitude": f"{zone.latitude:.4f}", "longitude": f"{zone.longitude:.4f}",
                    "current": "temperature_2m,relative_humidity_2m,precipitation,"
                               "weather_code,wind_speed_10m",
                    "timezone": "auto",
                },
                timeout=4.0, follow_redirects=False,
            )
            if response.status_code != 200:
                return None
            data = response.json()["current"]
            code = data["weather_code"]
            condition_code, label = condition(code)
            weather = CurrentWeatherDTO(
                temperature_c=data["temperature_2m"], humidity_percent=data["relative_humidity_2m"],
                precipitation_mm=data["precipitation"], wind_speed_kmh=data["wind_speed_10m"],
                weather_code=code, condition_code=condition_code, condition_label=label,
                observed_at=data.get("time"),
            )
        except (httpx.HTTPError, ValueError, KeyError, TypeError, OverflowError, RecursionError):
            return None
        self.cache.put(key, weather)
        return weather
