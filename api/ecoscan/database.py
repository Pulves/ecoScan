from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine

from ecoscan.models import table_registry
from ecoscan.settings import Settings

engine = create_async_engine(Settings().DATABASE_URL, future=True)


async def create_database_schema() -> None:
    async with engine.begin() as connection:
        await connection.run_sync(table_registry.metadata.create_all)


async def close_database() -> None:
    await engine.dispose()


async def get_session():
    async with AsyncSession(engine, expire_on_commit=False) as session:
        yield session
