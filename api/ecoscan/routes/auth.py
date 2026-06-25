from datetime import UTC, datetime, timedelta
from hashlib import sha256
from http import HTTPStatus
import logging
from secrets import token_urlsafe
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException
from fastapi.security import OAuth2PasswordRequestForm
from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession


from ecoscan.email_service import send_password_reset_email
from ecoscan.models import PasswordResetToken, User
from ecoscan.schemas import (
    Message,
    PasswordResetRequestResponseSchema,
    PasswordResetRequestSchema,
    PasswordResetSchema,
    TokenSchema,
)
from ecoscan.database import get_session

from ecoscan.security import (
    create_access_token,
    create_refresh_token,
    get_current_user_from_refresh_token,
    verify_password,
    get_password_hash,
)
from ecoscan.settings import Settings

Oauth2Form = Annotated[OAuth2PasswordRequestForm, Depends()]
Session = Annotated[AsyncSession, Depends(get_session)]

Refresh_User = Annotated[User, Depends(get_current_user_from_refresh_token)]

router = APIRouter(prefix="/auth", tags=["auth"])
settings = Settings()
logger = logging.getLogger(__name__)


@router.post("/token", response_model=TokenSchema)
async def login(form_data: Oauth2Form, session: Session):

    user = await session.scalar(select(User).where(User.email == form_data.username))
    if not user:
        raise HTTPException(status_code=HTTPStatus.UNAUTHORIZED, detail="Incorrect email or password")
    
    if not verify_password(form_data.password, user.password):
        raise HTTPException(status_code=HTTPStatus.UNAUTHORIZED, detail="Incorrect email or password")
    
    access_token = create_access_token(data={"sub": user.email})
    refresh_token = create_refresh_token(data={"sub": user.email})
    return {
        "access_token": access_token,
        "refresh_token": refresh_token,
        "token_type": "bearer",
    }


@router.post("/refresh", response_model=TokenSchema)   
def refresh_token(current_user: Refresh_User):
    access_token = create_access_token(data={"sub": current_user.email})
    refresh_token = create_refresh_token(data={"sub": current_user.email})
    return {
        "access_token": access_token,
        "refresh_token": refresh_token,
        "token_type": "bearer",
    }


@router.post(
    "/password-reset/request",
    response_model=PasswordResetRequestResponseSchema,
)
async def request_password_reset(
    request: PasswordResetRequestSchema,
    session: Session,
) -> dict[str, str | None]:
    reset_token: str | None = None
    user = await session.scalar(select(User).where(User.email == request.email))
    if user is not None:
        await session.execute(
            update(PasswordResetToken)
            .where(
                PasswordResetToken.user_id == user.id,
                PasswordResetToken.used_at.is_(None),
            )
            .values(used_at=datetime.now(UTC))
        )
        reset_token = token_urlsafe(32)
        session.add(
            PasswordResetToken(
                token_hash=sha256(reset_token.encode()).hexdigest(),
                user_id=user.id,
                expires_at=datetime.now(UTC)
                + timedelta(
                    minutes=settings.PASSWORD_RESET_TOKEN_EXPIRE_MINUTES
                ),
            )
        )
        await session.commit()
        if not settings.PASSWORD_RESET_EXPOSE_TOKEN:
            try:
                await send_password_reset_email(
                    user.email,
                    reset_token,
                    settings,
                )
            except Exception as error:
                logger.exception(
                    "Nao foi possivel enviar o email de recuperacao."
                )
                raise HTTPException(
                    status_code=HTTPStatus.SERVICE_UNAVAILABLE,
                    detail=(
                        "O servico de recuperacao por email esta "
                        "temporariamente indisponivel."
                    ),
                ) from error

    return {
        "message": (
            "Se o email estiver cadastrado, as instrucoes de recuperacao "
            "foram geradas."
        ),
        "reset_token": (
            reset_token if settings.PASSWORD_RESET_EXPOSE_TOKEN else None
        ),
    }


@router.post("/password-reset/confirm", response_model=Message)
async def confirm_password_reset(
    reset: PasswordResetSchema,
    session: Session,
) -> dict[str, str]:
    token_hash = sha256(reset.token.encode()).hexdigest()
    stored_token = await session.scalar(
        select(PasswordResetToken).where(
            PasswordResetToken.token_hash == token_hash,
            PasswordResetToken.used_at.is_(None),
        )
    )
    now = datetime.now(UTC)
    if stored_token is None or stored_token.expires_at < now:
        raise HTTPException(
            status_code=HTTPStatus.BAD_REQUEST,
            detail="Token de recuperacao invalido ou expirado.",
        )

    user = await session.get(User, stored_token.user_id)
    if user is None:
        raise HTTPException(
            status_code=HTTPStatus.BAD_REQUEST,
            detail="Token de recuperacao invalido.",
        )

    user.password = get_password_hash(reset.new_password)
    stored_token.used_at = now
    session.add_all([user, stored_token])
    await session.commit()
    return {"message": "Senha alterada com sucesso."}
