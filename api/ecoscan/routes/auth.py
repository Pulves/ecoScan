from http import HTTPStatus
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException
from fastapi.security import OAuth2PasswordRequestForm
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession


from ecoscan.models import User
from ecoscan.schemas import TokenSchema
from ecoscan.database import get_session

from ecoscan.security import create_access_token, verify_password, get_current_user

Oauth2Form = Annotated[OAuth2PasswordRequestForm, Depends()]
Session = Annotated[AsyncSession, Depends(get_session)]

Current_User = Annotated[User, Depends(get_current_user)]

router = APIRouter(prefix="/auth", tags=["auth"])


@router.post("/token", response_model=TokenSchema)
async def login(form_data: Oauth2Form, session: Session):

    user = await session.scalar(select(User).where(User.email == form_data.username))
    if not user:
        raise HTTPException(status_code=HTTPStatus.UNAUTHORIZED, detail="Incorrect email or password")
    
    if not verify_password(form_data.password, user.password):
        raise HTTPException(status_code=HTTPStatus.UNAUTHORIZED, detail="Incorrect email or password")
    
    access_token = create_access_token(data={"sub": user.email})
    return {"access_token": access_token, "token_type": "bearer"}


@router.post("/refresh", response_model=TokenSchema)   
def refresh_token(current_user: User = Depends(get_current_user)):
    access_token = create_access_token(data={"sub": current_user.email})
    return {"access_token": access_token, "token_type": "bearer"}
