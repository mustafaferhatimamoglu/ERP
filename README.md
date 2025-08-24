# ERP Monorepo (Auth + MQTT + PostgreSQL)

Bu depo, mikroservis tabanlı ERP için ilk adımı olan "auth" servisini içerir. Servis; FastAPI, PostgreSQL (async), ve MQTT (Mosquitto) entegrasyonu barındırır ve basit bir HTML giriş sayfası sağlar.

## Yapı
- `services/auth`: Kimlik doğrulama servisi
  - FastAPI uygulaması (`app.py`)
  - SQLAlchemy (2.x, async) modelleri (`models.py`) ve bağlantı (`db.py`)
  - Parola güvenliği (`security.py`)
  - MQTT istemcisi (`mqtt_client.py`)
  - HTML şablonları ve stil (`templates`, `static`)

## .env
Kök dizindeki `.env.example` dosyasını `.env` olarak kopyalayın ve değerleri düzenleyin.

Önemli alanlar:
- `DATABASE_URL`: `postgresql+asyncpg://erp_user:1q@<SERVER_IP>:5432/erp_dev`
- `SECRET_KEY`: Oturum (session) için gerekli.
- `MQTT_HOST`, `MQTT_PORT`: Mosquitto broker bilgileri.
- `ADMIN_USERNAME`, `ADMIN_PASSWORD`: İlk çalıştırmada otomatik admin oluşturma.

## Çalıştırma (Geliştirme)
Poetry veya pip ile kurulumu yapabilirsiniz.

### Pip ile
```
python -m venv .venv
source .venv/bin/activate
pip install --upgrade pip
pip install fastapi "uvicorn[standard]" SQLAlchemy asyncpg "passlib[bcrypt]" jinja2 pydantic-settings paho-mqtt python-multipart
export PYTHONPATH=.
cp .env.example .env  # düzenleyin
uvicorn services.auth.app:app --reload --host 0.0.0.0 --port 8000
```

### Poetry ile
```
cd services/auth
poetry install
cd ../..
export PYTHONPATH=.
cp .env.example .env  # düzenleyin
poetry run uvicorn services.auth.app:app --reload --host 0.0.0.0 --port 8000
```

Ardından `http://localhost:8000/login` adresine gidin. Giriş başarılı olduğunda MQTT'ye `auth/login` topiğinde event yayınlanır.

## Veritabanı
- Servis ilk açılışta tabloyu oluşturur.
- `.env` ile sağlanan `ADMIN_USERNAME` ve `ADMIN_PASSWORD` varsa, yoksa yeni bir admin kullanıcısı açılır.

## MQTT
- Broker erişilemiyorsa servis yine de çalışır; eventler sessizce atlanır.
- Konu: `auth/login` (payload: `{ username, user_id?, success }`).

## Sonraki Adımlar
- API tabanlı JWT (isteğe bağlı) eklenebilir.
- Kullanıcı kayıt/şifre sıfırlama uçları.
- Ters proxy ve prod yapılandırmaları (Docker, compose).

## Masaüstü Login İstemcisi (EXE)
- Kod: `clients/login_app/main.py`
- Kurulum:
  - `python -m venv .venv && source .venv/bin/activate`
  - `pip install -r clients/login_app/requirements.txt`
- Çalıştırma: `python clients/login_app/main.py`
- Sunucu URL: `http://<SUNUCU_IP>:8000`
- EXE paketleme (Windows):
  - `pip install pyinstaller`
  - `pyinstaller -F -n ERPLoginClient clients/login_app/main.py`
  - Çıktı: `dist/ERPLoginClient.exe`

