from __future__ import annotations

import logging
import os
from contextlib import asynccontextmanager
from typing import AsyncIterator

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from ecoscan.plant_classifier import PlantClassifier
from ecoscan.routes.plants import router as plants_router


logger = logging.getLogger(__name__)


def create_app(classifier: PlantClassifier | None = None) -> FastAPI:
    @asynccontextmanager
    async def lifespan(app: FastAPI) -> AsyncIterator[None]:
        service = classifier or PlantClassifier.from_environment()
        logger.info("Carregando modelo em %s", service.model_path)
        service.load()
        app.state.plant_classifier = service
        logger.info("Modelo carregado; API pronta para receber imagens.")
        yield

    app = FastAPI(
        title="EcoScan Plant Recognition API",
        version="1.0.0",
        description=(
            "API local para classificar imagens de plantas com o modelo "
            "YOLO11 treinado no arquivo best.pt."
        ),
        lifespan=lifespan,
    )
    app.add_middleware(
        CORSMiddleware,
        allow_origins=["*"],
        allow_credentials=False,
        allow_methods=["GET", "POST"],
        allow_headers=["*"],
    )
    app.include_router(plants_router)

    @app.get("/", tags=["service"])
    async def root() -> dict[str, str]:
        return {
            "service": "EcoScan Plant Recognition API",
            "health": "/plants/health",
            "identify": "/plants/identify",
            "documentation": "/docs",
        }

    return app


app = create_app()


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(
        app,
        host=os.getenv("ECOSCAN_HOST", "0.0.0.0"),
        port=int(os.getenv("ECOSCAN_PORT", "8000")),
    )
