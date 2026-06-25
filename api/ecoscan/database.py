import asyncio
from pathlib import Path

from alembic import command
from alembic.config import Config
from sqlalchemy import create_engine, inspect
from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine

from ecoscan.settings import Settings


settings = Settings()
engine = create_async_engine(settings.DATABASE_URL, future=True)


def _alembic_config() -> Config:
    config = Config(str(Path(__file__).with_name("alembic.ini")))
    config.set_main_option("sqlalchemy.url", settings.DATABASE_URL)
    return config


def _upgrade_database() -> None:
    config = _alembic_config()
    sync_engine = create_engine(settings.DATABASE_URL, future=True)
    try:
        with sync_engine.connect() as connection:
            tables = set(inspect(connection).get_table_names())
        if "users" in tables and "alembic_version" not in tables:
            baseline = "0002" if "identifications" in tables else "0001"
            command.stamp(config, baseline)
        command.upgrade(config, "head")
    finally:
        sync_engine.dispose()


async def run_database_migrations() -> None:
    await asyncio.to_thread(_upgrade_database)


async def close_database() -> None:
    await engine.dispose()


async def get_session():
    async with AsyncSession(engine, expire_on_commit=False) as session:
        yield session
