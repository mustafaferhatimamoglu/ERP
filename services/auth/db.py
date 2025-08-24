from typing import AsyncIterator

from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.orm import DeclarativeBase
import os


def _normalize_dsn(dsn: str) -> str:
    # Ensure async driver
    if dsn.startswith("postgresql://"):
        return dsn.replace("postgresql://", "postgresql+asyncpg://", 1)
    return dsn


DATABASE_URL = _normalize_dsn(os.getenv("DATABASE_URL", "postgresql+asyncpg://erp_user:1q@localhost:5432/erp_dev"))


class Base(DeclarativeBase):
    pass


async_engine = create_async_engine(DATABASE_URL, pool_pre_ping=True)
SessionLocal = async_sessionmaker(async_engine, class_=AsyncSession, expire_on_commit=False)


async def get_session() -> AsyncIterator[AsyncSession]:
    async with SessionLocal() as session:
        yield session

