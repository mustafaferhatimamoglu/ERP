import argparse
import asyncio
from typing import Optional

from .db import SessionLocal, Base, async_engine
from .models import User, Role, UserRole
from .security import get_password_hash
from sqlalchemy import select


async def ensure_tables() -> None:
    async with async_engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)


async def create_or_update_user(username: str, password: Optional[str] = None, is_active: Optional[bool] = None) -> User:
    async with SessionLocal() as session:
        res = await session.execute(select(User).where(User.username == username))
        user = res.scalar_one_or_none()
        if not user:
            user = User(username=username, password_hash=get_password_hash(password or "changeme"), is_active=True)
            session.add(user)
        else:
            if password is not None:
                user.password_hash = get_password_hash(password)
            if is_active is not None:
                user.is_active = is_active
        await session.commit()
        return user


async def assign_admin(username: str) -> None:
    async with SessionLocal() as session:
        res = await session.execute(select(User).where(User.username == username))
        user = res.scalar_one_or_none()
        if not user:
            raise SystemExit(f"User not found: {username}")
        r = await session.execute(select(Role).where(Role.name == "admin"))
        role = r.scalar_one_or_none()
        if not role:
            role = Role(name="admin")
            session.add(role)
            await session.commit()
        ur = await session.execute(select(UserRole).where(UserRole.user_id == user.id, UserRole.role_id == role.id))
        if not ur.scalar_one_or_none():
            session.add(UserRole(user_id=user.id, role_id=role.id))
            await session.commit()


async def list_users() -> None:
    async with SessionLocal() as session:
        res = await session.execute(select(User).order_by(User.id))
        users = res.scalars().all()
        for u in users:
            print(f"{u.id}\t{u.username}\tactive={u.is_active}")


def main():
    parser = argparse.ArgumentParser(description="ERP Auth management")
    sub = parser.add_subparsers(dest="cmd", required=True)

    ca = sub.add_parser("create-admin", help="Create or update admin user and assign admin role")
    ca.add_argument("--username", required=True)
    ca.add_argument("--password", required=True)

    sp = sub.add_parser("set-password", help="Set password for a user")
    sp.add_argument("--username", required=True)
    sp.add_argument("--password", required=True)

    lu = sub.add_parser("list-users", help="List users")

    args = parser.parse_args()

    if args.cmd == "create-admin":
        asyncio.run(ensure_tables())
        asyncio.run(create_or_update_user(args.username, args.password, True))
        asyncio.run(assign_admin(args.username))
        print("Admin kullanıcı hazır.")
    elif args.cmd == "set-password":
        asyncio.run(create_or_update_user(args.username, args.password))
        print("Şifre güncellendi.")
    elif args.cmd == "list-users":
        asyncio.run(list_users())


if __name__ == "__main__":
    main()

