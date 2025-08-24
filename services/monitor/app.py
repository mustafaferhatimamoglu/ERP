import asyncio
import json
from typing import List

from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.responses import HTMLResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from starlette.requests import Request

import paho.mqtt.client as mqtt
import os


MQTT_HOST = os.getenv("MONITOR_MQTT_HOST", os.getenv("MQTT_HOST", "127.0.0.1"))
MQTT_PORT = int(os.getenv("MONITOR_MQTT_PORT", os.getenv("MQTT_PORT", "1883")))
MQTT_USER = os.getenv("MONITOR_MQTT_USERNAME", os.getenv("MQTT_USERNAME", "")) or None
MQTT_PASS = os.getenv("MONITOR_MQTT_PASSWORD", os.getenv("MQTT_PASSWORD", "")) or None
MQTT_CLIENT_ID = os.getenv("MONITOR_MQTT_CLIENT_ID", "erp-monitor")


app = FastAPI(title="ERP Monitor Service")

templates = Jinja2Templates(directory="services/monitor/templates")
app.mount("/static", StaticFiles(directory="services/monitor/static"), name="static")


class EventHub:
    def __init__(self) -> None:
        self._clients: List[asyncio.Queue] = []
        self._lock = asyncio.Lock()

    async def connect(self) -> asyncio.Queue:
        q: asyncio.Queue = asyncio.Queue()
        async with self._lock:
            self._clients.append(q)
        return q

    async def disconnect(self, q: asyncio.Queue) -> None:
        async with self._lock:
            if q in self._clients:
                self._clients.remove(q)

    async def broadcast(self, message: dict) -> None:
        async with self._lock:
            for q in list(self._clients):
                await q.put(message)


hub = EventHub()


def _on_connect(client, userdata, flags, reason_code, properties):  # noqa: ANN001
    if reason_code == 0:
        client.subscribe("auth/login")


def _on_message(client, userdata, msg):  # noqa: ANN001
    try:
        payload = json.loads(msg.payload.decode("utf-8"))
    except Exception:
        payload = {"raw": msg.payload.decode("utf-8", errors="ignore")}
    data = {"topic": msg.topic, "payload": payload}
    asyncio.get_event_loop().create_task(hub.broadcast(data))


def start_mqtt():
    client = mqtt.Client(client_id=MQTT_CLIENT_ID, callback_api_version=mqtt.CallbackAPIVersion.VERSION2)
    if MQTT_USER and MQTT_PASS:
        client.username_pw_set(MQTT_USER, MQTT_PASS)
    client.on_connect = _on_connect
    client.on_message = _on_message
    rc = client.connect(MQTT_HOST, MQTT_PORT, keepalive=30)
    if rc != mqtt.MQTT_ERR_SUCCESS:
        raise RuntimeError("Monitor: MQTT broker'a bağlanılamadı")
    client.loop_start()
    return client


@app.on_event("startup")
async def _startup():
    app.state.mqtt_client = start_mqtt()


@app.on_event("shutdown")
async def _shutdown():
    client = getattr(app.state, "mqtt_client", None)
    if client:
        try:
            client.loop_stop()
            client.disconnect()
        except Exception:
            pass


@app.get("/", response_class=HTMLResponse)
async def index(request: Request):
    return templates.TemplateResponse("index.html", {"request": request})


@app.websocket("/ws")
async def ws_endpoint(ws: WebSocket):
    await ws.accept()
    q = await hub.connect()
    try:
        while True:
            msg = await q.get()
            await ws.send_json(msg)
    except WebSocketDisconnect:
        pass
    finally:
        await hub.disconnect(q)


@app.get("/server-ip")
async def server_ip():
    import socket
    host = socket.gethostname()
    try:
        addrs = list({addr for addr in socket.gethostbyname_ex(host)[2] if not addr.startswith("127.")})
    except Exception:
        addrs = []
    return {"server_ips": addrs}
