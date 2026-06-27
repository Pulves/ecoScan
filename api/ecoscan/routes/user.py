from http import HTTPStatus
from typing import Annotated


from ecoscan.security import get_password_hash, get_current_user
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from fastapi import APIRouter, Depends, HTTPException

from ecoscan.models import User
from ecoscan.validators import UserFieldsValidator, EmailValidator, NameValidator
from ecoscan.schemas import UserSchema, UserResponseSchema, UserUpdateSchema
from ecoscan.database import get_session
router = APIRouter(prefix="/users", tags=["users"])

Session = Annotated[AsyncSession, Depends(get_session)]
Current_User = Annotated[User, Depends(get_current_user)]

@router.post("/", status_code=HTTPStatus.CREATED, response_model=UserResponseSchema)
async def create_user(user: UserSchema, session: Session):

    if not UserFieldsValidator.is_valid(user):
        raise HTTPException(status_code=HTTPStatus.BAD_REQUEST, detail="Dados do usuário inválidos")

    
    try:
        db_user = await session.scalar(select(User).where(
            (User.email == user.email )| (User.name == user.name)
            ))
        
    except Exception as e:
        print(f"Error checking existing user: {e}")
        raise HTTPException(status_code=HTTPStatus.INTERNAL_SERVER_ERROR, detail="Erro no servidor")
        
    if db_user:
        raise HTTPException(status_code=HTTPStatus.CONFLICT, 
                            detail="nome do usuário ou email já existe")
    
    password_hash = get_password_hash(user.password)
    new_user = User(name=user.name, email=user.email, password=password_hash)
  
    session.add(new_user)  
    
    try:
        await session.commit()      
        await session.refresh(new_user) 

    except Exception as e:
        await session.rollback()     
        print(f"Error saving new user: {e}")
        raise HTTPException(status_code=HTTPStatus.INTERNAL_SERVER_ERROR, detail="Erro ao criar usuário")

    return new_user


@router.get("/", status_code=HTTPStatus.OK, response_model=UserResponseSchema)
async def get_user(user: Current_User):
    return user


@router.put("/", status_code=HTTPStatus.OK, response_model=UserResponseSchema)
async def update_user(user_update: UserUpdateSchema,
                      session: Session,
                      current_user: Current_User):
    
    if not EmailValidator.is_valid(user_update.email):
        raise HTTPException(status_code=HTTPStatus.BAD_REQUEST, detail="Email inválido")
    
    if not NameValidator.is_valid(user_update.name):
        raise HTTPException(status_code=HTTPStatus.BAD_REQUEST, detail="Nome inválido")
    
    if not user_update.name or not user_update.email:
        raise HTTPException(status_code=HTTPStatus.BAD_REQUEST, detail="Nome e Email são obrigatórios")
    
    current_user.name = user_update.name
    current_user.email = user_update.email
    
    session.add(current_user)
    await session.commit()
    await session.refresh(current_user)
    return current_user
