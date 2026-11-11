from fastapi import APIRouter, Depends

from app.security import token_user

router = APIRouter(tags=["me"])


@router.get("/me")
def me(user: dict = Depends(token_user)):
    # Task 4 bổ sung consent và face (đặc tả mục 9.5).
    return {k: user[k] for k in ("id", "role", "username", "full_name", "email", "student_code", "must_change_password")}
