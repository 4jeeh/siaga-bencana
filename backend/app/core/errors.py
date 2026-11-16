from fastapi import Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from sqlalchemy.exc import OperationalError, TimeoutError
from starlette.exceptions import HTTPException


class ApiError(Exception):
    def __init__(self, status, code, message, details=None, headers=None):
        self.status = status
        self.code = code
        self.message = message
        self.details = details
        self.headers = headers or {}
        if status == 401:
            self.headers["WWW-Authenticate"] = "Bearer"


def error_response(request: Request, error: ApiError):
    return JSONResponse(
        status_code=error.status,
        content={
            "code": error.code,
            "message": error.message,
            "details": error.details,
            "request_id": request.state.request_id,
        },
        headers=error.headers,
    )


def install_handlers(app):
    @app.exception_handler(ApiError)
    async def api_error(request, exc):
        return error_response(request, exc)

    @app.exception_handler(RequestValidationError)
    async def invalid(request, exc):
        errors = exc.errors()
        if any(e["type"] == "json_invalid" for e in errors):
            return error_response(request, ApiError(400, "MALFORMED_REQUEST", "JSON tidak valid."))
        fields = [
            {"field": ".".join(str(p) for p in e["loc"] if p != "body"), "code": e["type"]}
            for e in errors
        ]
        return error_response(
            request,
            ApiError(422, "VALIDATION_ERROR", "Periksa kembali isian Anda.", {"fields": fields}),
        )

    @app.exception_handler(HTTPException)
    async def http_error(request, exc):
        code = {
            404: "RESOURCE_NOT_FOUND",
            401: "AUTH_REQUIRED",
            403: "FORBIDDEN",
            405: "METHOD_NOT_ALLOWED",
        }.get(exc.status_code, "MALFORMED_REQUEST")
        return error_response(
            request,
            ApiError(
                exc.status_code, code, "Permintaan tidak dapat diproses.", headers=exc.headers
            ),
        )

    @app.exception_handler(OperationalError)
    @app.exception_handler(TimeoutError)
    async def unavailable(request, exc):
        return error_response(
            request, ApiError(503, "SERVICE_UNAVAILABLE", "Layanan belum siap. Coba lagi sebentar.")
        )
