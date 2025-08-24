from contextlib import asynccontextmanager
import logging
from logging.handlers import RotatingFileHandler
from typing import Annotated, Optional

from fastapi import Depends, FastAPI, Form, HTTPException, Request, status, Body
from fastapi.responses import HTMLResponse, RedirectResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from starlette.middleware.sessions import SessionMiddleware

from .db import Base, async_engine, get_session, SessionLocal
from .models import User, Role, UserRole
from .security import verify_password, get_password_hash
from .settings import settings
from .mqtt_client import mqtt

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

# logging
logger = logging.getLogger("erp.auth")
if not logger.handlers:
    logger.setLevel(logging.INFO)
    _fh = RotatingFileHandler("auth_service.log", maxBytes=1024 * 1024, backupCount=3)
    _fmt = logging.Formatter("%(asctime)s [%(levelname)s] %(name)s: %(message)s")
    _fh.setFormatter(_fmt)
    logger.addHandler(_fh)
    logger.addHandler(logging.StreamHandler())


@asynccontextmanager
async def lifespan(app: FastAPI):
    # DB: create tables
    async with async_engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)

    # MQTT: connect (fail-fast)
    logger.info("Starting ERP Auth Service")
    if not mqtt.connect():
        logger.error("MQTT broker'a bağlanılamadı. Servis durduruluyor.")
        raise RuntimeError("MQTT broker'a bağlanılamadı. Servis durduruluyor.")

    # Optional: seed admin user on first run
    if settings.admin_username and settings.admin_password:
        async with SessionLocal() as session:
            await ensure_admin_user(session)

    yield

    # MQTT: disconnect
    mqtt.disconnect()


app = FastAPI(title="ERP Auth Service", lifespan=lifespan)
app.add_middleware(SessionMiddleware, secret_key=settings.secret_key)

templates = Jinja2Templates(directory="services/auth/templates")
app.mount("/static", StaticFiles(directory="services/auth/static"), name="static")


SessionDep = Annotated[AsyncSession, Depends(get_session)]


async def ensure_admin_user(session: AsyncSession) -> None:
    result = await session.execute(select(User).where(User.username == settings.admin_username))
    user = result.scalar_one_or_none()
    if not user:
        user = User(
            username=settings.admin_username,
            password_hash=get_password_hash(settings.admin_password),
            is_active=True,
        )
        session.add(user)
        await session.commit()
    # ensure 'admin' role exists
    r = await session.execute(select(Role).where(Role.name == "admin"))
    role = r.scalar_one_or_none()
    if not role:
        role = Role(name="admin")
        session.add(role)
        await session.commit()
    # ensure user has admin role
    ur = await session.execute(
        select(UserRole).where(UserRole.user_id == user.id, UserRole.role_id == role.id)
    )
    if not ur.scalar_one_or_none():
        session.add(UserRole(user_id=user.id, role_id=role.id))
        await session.commit()


@app.get("/", response_class=HTMLResponse)
async def index(request: Request):
    user_id = request.session.get("user_id")
    if not user_id:
        return RedirectResponse(url="/login", status_code=status.HTTP_302_FOUND)
    return RedirectResponse(url="/dashboard", status_code=status.HTTP_302_FOUND)


@app.get("/login", response_class=HTMLResponse)
async def login_page(request: Request):
    return templates.TemplateResponse("login.html", {"request": request, "error": None})


def require_mqtt():
    if not mqtt.is_connected:
        raise HTTPException(status_code=503, detail="MQTT bağlantısı yok")


@app.post("/login")
async def login(
    request: Request,
    session: SessionDep,
    username: Annotated[str, Form(...)],
    password: Annotated[str, Form(...)],
):
    require_mqtt()
    result = await session.execute(select(User).where(User.username == username))
    user: Optional[User] = result.scalar_one_or_none()
    if not user or not verify_password(password, user.password_hash):
        mqtt.publish("auth/login", {"username": username, "success": False})
        return templates.TemplateResponse(
            "login.html", {"request": request, "error": "Kullanıcı veya şifre hatalı"}, status_code=400
        )
    if not user.is_active:
        return templates.TemplateResponse(
            "login.html", {"request": request, "error": "Hesap pasif"}, status_code=403
        )

    request.session["user_id"] = user.id
    mqtt.publish("auth/login", {"user_id": user.id, "username": user.username, "success": True})
    return RedirectResponse(url="/dashboard", status_code=status.HTTP_302_FOUND)


@app.get("/logout")
async def logout(request: Request):
    require_mqtt()
    request.session.clear()
    return RedirectResponse(url="/login", status_code=status.HTTP_302_FOUND)


@app.get("/dashboard", response_class=HTMLResponse)
async def dashboard(request: Request, session: SessionDep):
    require_mqtt()
    user_id = request.session.get("user_id")
    if not user_id:
        return RedirectResponse(url="/login", status_code=status.HTTP_302_FOUND)

    user = await session.get(User, user_id)
    if not user:
        request.session.clear()
        return RedirectResponse(url="/login", status_code=status.HTTP_302_FOUND)

    return templates.TemplateResponse(
        "dashboard.html",
        {"request": request, "username": user.username},
    )


# Health endpoint for liveness/readiness probes
@app.get("/healthz")
async def healthz():
    return {"status": "ok"}


@app.post("/api/login")
async def api_login(session: SessionDep, payload: dict = Body(...)):
    require_mqtt()
    username = payload.get("username")
    password = payload.get("password")
    if not username or not password:
        raise HTTPException(status_code=400, detail="username/password gerekli")
    result = await session.execute(select(User).where(User.username == username))
    user: Optional[User] = result.scalar_one_or_none()
    if not user or not verify_password(password, user.password_hash):
        mqtt.publish("auth/login", {"username": username, "success": False})
        logger.info("API login failed for user=%s", username)
        return JSONResponse(status_code=401, content={"ok": False, "reason": "invalid_credentials"})
    if not user.is_active:
        logger.info("API login inactive user=%s", username)
        return JSONResponse(status_code=403, content={"ok": False, "reason": "inactive"})

    mqtt.publish("auth/login", {"user_id": user.id, "username": user.username, "success": True})
    logger.info("API login success user=%s id=%s", username, user.id)
    return {"ok": True, "user_id": user.id, "username": user.username}


def _is_admin(user_id: int, session: AsyncSession) -> bool:
    return False


async def require_admin(request: Request, session: AsyncSession) -> User:
    user_id = request.session.get("user_id")
    if not user_id:
        raise HTTPException(status_code=401)
    user = await session.get(User, user_id)
    if not user:
        raise HTTPException(status_code=401)
    # check role
    r = await session.execute(select(Role.id).where(Role.name == "admin"))
    role_id = r.scalar_one_or_none()
    if not role_id:
        raise HTTPException(status_code=403)
    ur = await session.execute(
        select(UserRole).where(UserRole.user_id == user.id, UserRole.role_id == role_id)
    )
    if not ur.scalar_one_or_none():
        raise HTTPException(status_code=403)
    return user


@app.get("/users", response_class=HTMLResponse)
async def users_page(request: Request, session: SessionDep):
    require_mqtt()
    await require_admin(request, session)
    result = await session.execute(select(User).order_by(User.id))
    users = result.scalars().all()
    return templates.TemplateResponse(
        "users.html",
        {"request": request, "users": users, "error": None},
    )


@app.post("/users/create", response_class=HTMLResponse)
async def users_create(
    request: Request,
    session: SessionDep,
    username: Annotated[str, Form(...)],
    password: Annotated[str, Form(...)],
    is_active: Annotated[bool, Form(False)] = True,
):
    require_mqtt()
    await require_admin(request, session)
    # validate unique username
    exists = await session.execute(select(User).where(User.username == username))
    if exists.scalar_one_or_none():
        result = await session.execute(select(User).order_by(User.id))
        users = result.scalars().all()
        return templates.TemplateResponse(
            "users.html",
            {"request": request, "users": users, "error": "Kullanıcı adı mevcut"},
            status_code=400,
        )
    user = User(username=username, password_hash=get_password_hash(password), is_active=is_active)
    session.add(user)
    await session.commit()
    return RedirectResponse(url="/users", status_code=status.HTTP_302_FOUND)


@app.post("/users/toggle/{user_id}")
async def users_toggle(request: Request, session: SessionDep, user_id: int):
    require_mqtt()
    await require_admin(request, session)
    user = await session.get(User, user_id)
    if not user:
        raise HTTPException(status_code=404)
    user.is_active = not user.is_active
    await session.commit()
    return RedirectResponse(url="/users", status_code=status.HTTP_302_FOUND)


@app.get("/server-ip")
async def server_ip(request: Request):
    import socket
    host = socket.gethostname()
    try:
        addrs = list({addr for addr in socket.gethostbyname_ex(host)[2] if not addr.startswith("127.")})
    except Exception:
        addrs = []
    return {
        "server_ips": addrs,
        "hint": "Uygulamaya http://<server_ip>:8000 ile erişin",
    }
