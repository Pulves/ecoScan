from __future__ import annotations

from http import HTTPStatus
from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, File, Form, HTTPException, Response, UploadFile
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from ecoscan.database import get_session
from ecoscan.models import Identification, User
from ecoscan.schemas import IdentificationResponseSchema
from ecoscan.security import get_current_user


MAX_IMAGE_BYTES = 10 * 1024 * 1024
ALLOWED_CONTENT_TYPES = {
    "application/octet-stream",
    "image/bmp",
    "image/jpeg",
    "image/png",
    "image/tiff",
    "image/webp",
}

history_router = APIRouter(prefix="/history", tags=["history"])
library_router = APIRouter(prefix="/library", tags=["library"])

Session = Annotated[AsyncSession, Depends(get_session)]
CurrentUser = Annotated[User, Depends(get_current_user)]


def _serialize(record: Identification) -> IdentificationResponseSchema:
    return IdentificationResponseSchema(
        id=record.id,
        plant_name=record.plant_name,
        plant_slug=record.plant_slug,
        confidence=record.confidence,
        recognized=record.recognized,
        created_at=record.created_at,
        in_library=record.in_library,
        image_url=f"/history/{record.id}/image",
    )


async def _owned_record(
    identification_id: UUID,
    session: AsyncSession,
    current_user: User,
) -> Identification:
    record = await session.scalar(
        select(Identification).where(
            Identification.id == identification_id,
            Identification.user_id == current_user.id,
        )
    )
    if record is None:
        raise HTTPException(
            status_code=HTTPStatus.NOT_FOUND,
            detail="Identificacao nao encontrada.",
        )
    return record


@history_router.post(
    "",
    status_code=HTTPStatus.CREATED,
    response_model=IdentificationResponseSchema,
)
async def create_history_record(
    session: Session,
    current_user: CurrentUser,
    image: Annotated[UploadFile, File(description="Imagem identificada.")],
    plant_name: Annotated[str, Form(min_length=1, max_length=255)],
    confidence: Annotated[float, Form(ge=0, le=1)],
    recognized: Annotated[bool, Form()],
    plant_slug: Annotated[str | None, Form(max_length=255)] = None,
    add_to_library: Annotated[bool, Form()] = True,
) -> IdentificationResponseSchema:
    content_type = (image.content_type or "application/octet-stream").lower()
    if content_type not in ALLOWED_CONTENT_TYPES:
        await image.close()
        raise HTTPException(
            status_code=HTTPStatus.UNSUPPORTED_MEDIA_TYPE,
            detail="Formato de imagem nao suportado.",
        )

    try:
        image_bytes = await image.read(MAX_IMAGE_BYTES + 1)
    finally:
        await image.close()

    if len(image_bytes) > MAX_IMAGE_BYTES:
        raise HTTPException(
            status_code=HTTPStatus.REQUEST_ENTITY_TOO_LARGE,
            detail="A imagem excede o limite de 10 MB.",
        )

    record = Identification(
        plant_name=plant_name,
        plant_slug=plant_slug,
        confidence=confidence,
        recognized=recognized,
        image_data=image_bytes,
        image_content_type=content_type,
        user_id=current_user.id,
        in_library=add_to_library,
    )
    session.add(record)
    await session.commit()
    await session.refresh(record)
    return _serialize(record)


@history_router.get(
    "",
    response_model=list[IdentificationResponseSchema],
)
async def list_history(
    session: Session,
    current_user: CurrentUser,
) -> list[IdentificationResponseSchema]:
    records = await session.scalars(
        select(Identification)
        .where(Identification.user_id == current_user.id)
        .order_by(Identification.created_at.desc())
    )
    return [_serialize(record) for record in records.all()]


@history_router.get("/{identification_id}/image")
async def get_history_image(
    identification_id: UUID,
    session: Session,
    current_user: CurrentUser,
) -> Response:
    record = await _owned_record(identification_id, session, current_user)
    return Response(
        content=record.image_data,
        media_type=record.image_content_type,
        headers={"Cache-Control": "private, max-age=3600"},
    )


@history_router.delete(
    "/{identification_id}",
    status_code=HTTPStatus.NO_CONTENT,
)
async def delete_history_record(
    identification_id: UUID,
    session: Session,
    current_user: CurrentUser,
) -> Response:
    record = await _owned_record(identification_id, session, current_user)
    await session.delete(record)
    await session.commit()
    return Response(status_code=HTTPStatus.NO_CONTENT)


@library_router.get(
    "",
    response_model=list[IdentificationResponseSchema],
)
async def list_library(
    session: Session,
    current_user: CurrentUser,
) -> list[IdentificationResponseSchema]:
    records = await session.scalars(
        select(Identification)
        .where(
            Identification.user_id == current_user.id,
            Identification.in_library.is_(True),
        )
        .order_by(Identification.created_at.desc())
    )
    return [_serialize(record) for record in records.all()]


@library_router.put(
    "/{identification_id}",
    response_model=IdentificationResponseSchema,
)
async def add_to_library(
    identification_id: UUID,
    session: Session,
    current_user: CurrentUser,
) -> IdentificationResponseSchema:
    record = await _owned_record(identification_id, session, current_user)
    record.in_library = True
    session.add(record)
    await session.commit()
    await session.refresh(record)
    return _serialize(record)


@library_router.delete(
    "/{identification_id}",
    status_code=HTTPStatus.NO_CONTENT,
)
async def remove_from_library(
    identification_id: UUID,
    session: Session,
    current_user: CurrentUser,
) -> Response:
    record = await _owned_record(identification_id, session, current_user)
    record.in_library = False
    session.add(record)
    await session.commit()
    return Response(status_code=HTTPStatus.NO_CONTENT)
