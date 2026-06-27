from http import HTTPStatus
from typing import Annotated
import io
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession
from fastapi import APIRouter, Depends, HTTPException, UploadFile, File
from ecoscan.models import Plant, User
from ecoscan.schemas import FichaTecnicaSchema
from ecoscan.database import get_session
from ecoscan.security import get_current_user

from ai.llmConnection import get_ficha_tecnica


router = APIRouter(prefix="/plants", tags=["plants"])
Image_Input = Annotated[UploadFile, File()]

Session = Annotated[AsyncSession, Depends(get_session)]
Current_User = Annotated[User, Depends(get_current_user)]

@router.post("/identify", response_model=FichaTecnicaSchema)
async def identify_plant(image: Image_Input):
    
    if not image.content_type.startswith("image/"):
        raise HTTPException(status_code=HTTPStatus.BAD_REQUEST, detail="O arquivo enviado não é uma imagem.")
    
    if not image:
        raise HTTPException(status_code=HTTPStatus.BAD_REQUEST, detail="Nenhuma imagem foi enviada.")
    
    try:
        image_data = await image.read()
        ficha_tecnica = get_ficha_tecnica(image_data)
        return ficha_tecnica
    except Exception as e:
        print(f"Erro ao processar a imagem: {e}")
        raise HTTPException(status_code=HTTPStatus.INTERNAL_SERVER_ERROR, detail="Erro ao processar a imagem.")