from __future__ import annotations

import secrets
from typing import Optional
from urllib.parse import quote

from fastapi import Depends, Request
from fastapi.security import HTTPBasic, HTTPBasicCredentials

from .config import settings

_basic = HTTPBasic(auto_error=False)


class LoginRequired(Exception):
    def __init__(self, next_url: str = "/"):
        self.next_url = next_url or "/"


def verify_password(username: str, password: str) -> bool:
    user_ok = secrets.compare_digest(username or "", settings.sudreg_ui_user)
    pass_ok = secrets.compare_digest(password or "", settings.sudreg_ui_password)
    return user_ok and pass_ok


def session_user(request: Request) -> Optional[str]:
    return request.session.get("user")


def require_user(request: Request) -> str:
    user = session_user(request)
    if user:
        return user
    raise LoginRequired(next_url=str(request.url.path))


def require_user_or_basic(
    request: Request,
    credentials: Optional[HTTPBasicCredentials] = Depends(_basic),
) -> str:
    from fastapi import HTTPException, status

    user = session_user(request)
    if user:
        return user
    if credentials and verify_password(credentials.username, credentials.password):
        return credentials.username
    raise HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Unauthorized",
        headers={"WWW-Authenticate": "Basic"},
    )


def logout(request: Request) -> None:
    request.session.clear()


def login_redirect_url(next_url: str) -> str:
    return f"/login?next={quote(next_url or '/', safe='')}"
