from typing import Literal

from pydantic import BaseModel, ConfigDict


class CurrentWeatherDTO(BaseModel):
    model_config = ConfigDict(allow_inf_nan=False, strict=True)
    temperature_c: float
    humidity_percent: int | None = None
    precipitation_mm: float | None = None
    wind_speed_kmh: float | None = None
    weather_code: int
    condition_code: Literal[
        "clear", "partly_cloudy", "cloudy", "fog", "drizzle", "rain", "heavy_rain",
        "thunderstorm", "unknown",
    ]
    condition_label: str
    observed_at: str | None = None
    source: Literal["OPEN_METEO"] = "OPEN_METEO"
    is_cached: bool = False
