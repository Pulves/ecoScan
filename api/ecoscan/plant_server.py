from __future__ import annotations

import asyncio
import logging
import os
from contextlib import asynccontextmanager
from typing import AsyncIterator

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from starlette.middleware.trustedhost import TrustedHostMiddleware

from ecoscan.database import close_database, run_database_migrations
from ecoscan.plant_classifier import PlantClassifier
from ecoscan.routes import auth, user
from ecoscan.routes.plants import router as plants_router
from ecoscan.routes.records import history_router, library_router
from ecoscan.settings import Settings


logger = logging.getLogger(__name__)

if os.name == "nt":
    asyncio.set_event_loop_policy(asyncio.WindowsSelectorEventLoopPolicy())


def event_loop_factory() -> asyncio.AbstractEventLoop:
    if os.name == "nt":
        return asyncio.SelectorEventLoop()
    return asyncio.new_event_loop()


def create_app(
    classifier: PlantClassifier | None = None,
    *,
    initialize_database: bool = True,
    app_settings: Settings | None = None,
) -> FastAPI:
    settings = app_settings or Settings()
    settings.validate_production()

    @asynccontextmanager
    async def lifespan(app: FastAPI) -> AsyncIterator[None]:
        if initialize_database:
            await run_database_migrations()
            logger.info("Migracoes do banco de dados aplicadas.")

        service = classifier or PlantClassifier.from_environment()
        app.state.plant_classifier = service
        app.state.plant_classifier_error = None

        try:
            logger.info("Carregando modelo em %s", service.model_path)
            service.load()
            logger.info("Modelo carregado; API pronta para receber imagens.")
        except (FileNotFoundError, RuntimeError) as exc:
            app.state.plant_classifier_error = str(exc)
            logger.warning("Classificador indisponivel: %s", exc)

        try:
            yield
        finally:
            if initialize_database:
                await close_database()

    app = FastAPI(
        title="EcoScan API",
        version="1.0.0",
        description=(
            "API unificada para usuarios, autenticacao e classificacao "
            "de plantas com YOLO11."
        ),
        lifespan=lifespan,
        docs_url="/docs" if settings.API_DOCS_ENABLED else None,
        redoc_url="/redoc" if settings.API_DOCS_ENABLED else None,
        openapi_url="/openapi.json" if settings.API_DOCS_ENABLED else None,
    )
    app.add_middleware(
        TrustedHostMiddleware,
        allowed_hosts=settings.allowed_hosts,
    )
    if settings.cors_allowed_origins:
        app.add_middleware(
            CORSMiddleware,
            allow_origins=settings.cors_allowed_origins,
            allow_credentials=False,
            allow_methods=["GET", "POST", "PUT", "DELETE", "OPTIONS"],
            allow_headers=["Authorization", "Content-Type"],
        )
    app.include_router(user.router)
    app.include_router(auth.router)
    app.include_router(plants_router)
    app.include_router(history_router)
    app.include_router(library_router)

    @app.get("/", tags=["service"])
    async def root() -> dict[str, object]:
        return {
            "service": "EcoScan API",
            "status": "ready",
            "users": "/users/",
            "authentication": "/auth/token",
            "health": "/plants/health",
            "identify": "/plants/identify",
            "history": "/history",
            "library": "/library",
            "documentation": "/docs" if settings.API_DOCS_ENABLED else None,
        }

    return app


app = create_app()


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(
        app,
        host=os.getenv("ECOSCAN_HOST", "0.0.0.0"),
        port=int(os.getenv("ECOSCAN_PORT", "8000")),
        loop=event_loop_factory,
    )
