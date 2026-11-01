from typing import AsyncIterator

from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.orm import DeclarativeBase
import os


def _normalize_dsn(dsn: str) -> str:
    # Ensure async driver for PostgreSQL DSN
    if dsn.startswith("postgresql://"):
        return dsn.replace("postgresql://", "postgresql+asyncpg://", 1)
    return dsn


raw_dsn = os.getenv("DATABASE_URL", "postgresql://erp_user:1q@localhost:5432/erp_dev")
if raw_dsn.startswith("sqlite"):
    raise RuntimeError("SQLite dev modu devre dışı. Sadece PostgreSQL kullanın (DATABASE_URL=postgresql://...)")

DATABASE_URL = _normalize_dsn(raw_dsn)
if not DATABASE_URL.startswith("postgresql+asyncpg://"):
    raise RuntimeError("Yalnızca PostgreSQL (asyncpg) desteklenir. Örn: postgresql://user:pass@host:5432/db")


class Base(DeclarativeBase):
    pass


async_engine = create_async_engine(DATABASE_URL, pool_pre_ping=True)
SessionLocal = async_sessionmaker(async_engine, class_=AsyncSession, expire_on_commit=False)


async def get_session() -> AsyncIterator[AsyncSession]:
    async with SessionLocal() as session:
        yield session
