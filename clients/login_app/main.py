import json
import logging
from logging.handlers import RotatingFileHandler
from pathlib import Path
from typing import Optional

import PySimpleGUI as sg
import httpx


APP_TITLE = "ERP Login Client"
LOG_PATH = Path(__file__).resolve().parent / "login_app.log"


logger = logging.getLogger("erp.login_client")
logger.setLevel(logging.INFO)
_fh = RotatingFileHandler(LOG_PATH, maxBytes=1024 * 1024, backupCount=3)
_fmt = logging.Formatter("%(asctime)s [%(levelname)s] %(name)s: %(message)s")
_fh.setFormatter(_fmt)
logger.addHandler(_fh)
logger.addHandler(logging.StreamHandler())


def try_login(server: str, username: str, password: str) -> tuple[bool, str]:
    url = server.rstrip("/") + "/api/login"
    try:
        r = httpx.post(url, json={"username": username, "password": password}, timeout=5.0)
        if r.status_code == 200:
            data = r.json()
            logger.info("Login OK user=%s id=%s", data.get("username"), data.get("user_id"))
            return True, f"Giriş başarılı: {data.get('username')} (id:{data.get('user_id')})"
        else:
            try:
                data = r.json()
                reason = data.get("reason", r.text)
            except Exception:
                reason = r.text
            logger.info("Login FAIL user=%s reason=%s", username, reason)
            return False, f"Giriş başarısız: {reason}"
    except httpx.ConnectError:
        logger.error("Sunucuya bağlanılamadı: %s", url)
        return False, "Sunucuya bağlanılamadı"
    except httpx.ReadTimeout:
        logger.error("İstek zaman aşımına uğradı: %s", url)
        return False, "Zaman aşımı"
    except Exception as e:
        logger.exception("Beklenmeyen hata: %s", e)
        return False, f"Hata: {e}"  # noqa: TRY401


def main():
    sg.theme("DarkBlue14")
    layout = [
        [sg.Text("Sunucu URL"), sg.Input(key="server", default_text="http://127.0.0.1:8000", size=(40, 1))],
        [sg.Text("Kullanıcı"), sg.Input(key="username", size=(20, 1))],
        [sg.Text("Şifre   "), sg.Input(key="password", password_char="*", size=(20, 1))],
        [sg.Button("Giriş Yap", key="login", bind_return_key=True), sg.Text("", key="status", size=(50, 1))],
        [sg.Multiline(key="log", size=(60, 10), disabled=True, autoscroll=True)],
    ]

    window = sg.Window(APP_TITLE, layout, finalize=True)
    window["log"].print(f"Log dosyası: {LOG_PATH}")

    while True:
        event, values = window.read()
        if event is None:
            break
        if event == "login":
            server = values.get("server", "").strip()
            username = values.get("username", "").strip()
            password = values.get("password", "")
            if not server or not username or not password:
                window["status"].update("Lütfen tüm alanları doldurun")
                continue
            ok, msg = try_login(server, username, password)
            window["status"].update(msg)
            window["log"].print(msg)

    window.close()


if __name__ == "__main__":
    main()

