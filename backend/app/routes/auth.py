"""Authentication endpoints: login + current-user info."""
from __future__ import annotations

from fastapi import APIRouter

from ..auth_deps import CurrentUser
from ..models.schemas import LoginRequest, LoginResponse, UserInfo
from ..services import auth as auth_svc

router = APIRouter()


@router.post("/api/auth/login", response_model=LoginResponse)
def login(body: LoginRequest) -> LoginResponse:
    result = auth_svc.authenticate(body.username, body.password)
    return LoginResponse(**result)


@router.get("/api/auth/me", response_model=UserInfo)
def me(user: CurrentUser) -> UserInfo:
    return UserInfo(**auth_svc.user_dict(user))