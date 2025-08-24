import json
from typing import Any, Dict

import paho.mqtt.client as mqttlib

from .settings import settings


class Mqtt:
    def __init__(self):
        self._client = mqttlib.Client(
            client_id=settings.mqtt_client_id,
            callback_api_version=mqttlib.CallbackAPIVersion.VERSION2,
        )
        if settings.mqtt_username and settings.mqtt_password:
            self._client.username_pw_set(settings.mqtt_username, settings.mqtt_password)
        self._connected = False
        self._client.on_connect = self._on_connect
        self._client.on_disconnect = self._on_disconnect

    # callbacks
    def _on_connect(self, client, userdata, flags, reason_code, properties):  # noqa: ANN001
        self._connected = reason_code == 0

    def _on_disconnect(self, client, userdata, reason_code, properties):  # noqa: ANN001
        self._connected = False

    def connect(self) -> bool:
        try:
            # If broker is unreachable, this raises immediately
            rc = self._client.connect(host=settings.mqtt_host, port=settings.mqtt_port, keepalive=30)
            if rc != mqttlib.MQTT_ERR_SUCCESS:
                self._connected = False
                return False
            self._client.loop_start()
            self._connected = True
            return True
        except Exception:
            self._connected = False
            return False

    def disconnect(self):
        try:
            if self._connected:
                self._client.loop_stop()
                self._client.disconnect()
        finally:
            self._connected = False

    @property
    def is_connected(self) -> bool:
        return self._connected

    def publish(self, topic: str, payload: Dict[str, Any]):
        if not self._connected:
            raise RuntimeError("MQTT not connected")
        self._client.publish(topic, json.dumps(payload), qos=0, retain=False)


mqtt = Mqtt()
