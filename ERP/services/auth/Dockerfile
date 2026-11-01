FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app

COPY ./services/auth/pyproject.toml /app/services/auth/pyproject.toml
RUN pip install --upgrade pip && \
    pip install fastapi "uvicorn[standard]" SQLAlchemy asyncpg "passlib[bcrypt]" jinja2 pydantic-settings paho-mqtt python-multipart

COPY . /app

EXPOSE 8000
CMD ["uvicorn", "services.auth.app:app", "--host", "0.0.0.0", "--port", "8000"]

