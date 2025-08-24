from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", case_sensitive=False)

    # Web
    secret_key: str = "change-me"  # Session cookie encryption

    # Database
    database_url: str | None = None

    # MQTT
    mqtt_host: str = "localhost"
    mqtt_port: int = 1883
    mqtt_username: str | None = None
    mqtt_password: str | None = None
    mqtt_client_id: str = "erp-auth"

    # Initial admin
    admin_username: str | None = "admin"
    admin_password: str | None = "admin123"

    @property
    def dsn(self) -> str | None:
        return self.database_url


settings = Settings()

