from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine

from ecoscan.settings import Settings

engine = create_async_engine(Settings().DATABASE_URL, future=True)


async def get_session():
    async with AsyncSession(engine, expire_on_commit=False) as session:
        yield session
