import os

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware

from app import errors
from app.routers import admin, auth, faces, me

MAX_BODY_BYTES = 3 * 1024 * 1024

app = FastAPI(title="Điểm danh khuôn mặt + GPS")
errors.install(app)
app.include_router(auth.router)
app.include_router(me.router)
app.include_router(admin.router)
app.include_router(faces.router)

if os.environ.get("CORS_ORIGIN_REGEX"):
    app.add_middleware(CORSMiddleware, allow_origin_regex=os.environ["CORS_ORIGIN_REGEX"],
                       allow_methods=["*"], allow_headers=["*"])


@app.middleware("http")
async def limit_body(request: Request, call_next):
    # ponytail: chỉ chặn theo Content-Length; request chunked không khai báo độ dài sẽ lọt.
    # Production có Caddy request_body max_size chặn thêm; đếm byte khi stream nếu bỏ Caddy.
    if int(request.headers.get("content-length") or 0) > MAX_BODY_BYTES:
        return errors.error_response(413, "PAYLOAD_TOO_LARGE", "Dữ liệu gửi lên vượt quá 3 MB")
    return await call_next(request)
