from http import HTTPStatus
from typing import Annotated

from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession
from fastapi import APIRouter, Depends, HTTPException, Query
from ecoscan.models import Plant
from ecoscan.schemas import PlantCreate, PlantRead, PlantUpdate


router = APIRouter(prefix="/plants", tags=["plants"])


