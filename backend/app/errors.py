"""Định dạng lỗi chung (đặc tả mục 9.5): {"error": {"code", "message", "details"}}."""
from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from starlette.exceptions import HTTPException

_HTTP_CODES = {404: ("NOT_FOUND", "Không tìm thấy"), 405: ("METHOD_NOT_ALLOWED", "Phương thức không được hỗ trợ")}


class ApiError(Exception):
    def __init__(self, status: int, code: str, message: str, details: dict | None = None):
        self.status, self.code, self.message, self.details = status, code, message, details or {}


def error_response(status: int, code: str, message: str, details=None) -> JSONResponse:
    return JSONResponse({"error": {"code": code, "message": message, "details": details or {}}}, status_code=status)


def install(app: FastAPI) -> None:
    @app.exception_handler(ApiError)
    async def _api(_: Request, e: ApiError):
        return error_response(e.status, e.code, e.message, e.details)

    @app.exception_handler(RequestValidationError)
    async def _validation(_: Request, e: RequestValidationError):
        details = [{"field": ".".join(str(p) for p in err["loc"][1:]), "msg": err["msg"]} for err in e.errors()]
        return error_response(422, "VALIDATION_ERROR", "Dữ liệu gửi lên không hợp lệ", details)

    @app.exception_handler(HTTPException)
    async def _http(_: Request, e: HTTPException):
        code, message = _HTTP_CODES.get(e.status_code, ("HTTP_ERROR", str(e.detail)))
        return error_response(e.status_code, code, message)
