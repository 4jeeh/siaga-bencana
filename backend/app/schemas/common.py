from datetime import datetime
from typing import Generic, Literal, TypeVar

from pydantic import BaseModel

T = TypeVar("T")


class Meta(BaseModel):
    server_time: datetime
    mode: Literal["production_live", "local_live", "simulation"]
    is_simulated: bool


class Envelope(BaseModel, Generic[T]):
    data: T
    meta: Meta


class StatusData(BaseModel):
    status: Literal["ok", "ready"]


def response_meta(request):
    settings = request.app.state.settings
    return {
        "server_time": settings.domain_now(),
        "mode": settings.app_mode,
        "is_simulated": settings.app_mode == "simulation",
    }


def envelope(request, data):
    return {"data": data, "meta": response_meta(request)}
