from typing import Literal
from urllib.parse import urlparse

from pydantic_settings import BaseSettings, SettingsConfigDict


DEVELOPMENT_SECRET_KEY = "development-only-secret-key-change-before-production"
DEFAULT_DATABASE_URL = (
    "postgresql+psycopg://postgres:postgresPassword@localhost:5432/ecoscan"
)
DEFAULT_PUBLIC_BASE_URL = "http://localhost:8000"


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    DATABASE_URL: str = DEFAULT_DATABASE_URL
    ENVIRONMENT: Literal["development", "test", "production"] = "development"
    PUBLIC_BASE_URL: str = DEFAULT_PUBLIC_BASE_URL
    RENDER_EXTERNAL_HOSTNAME: str | None = None
    CORS_ALLOWED_ORIGINS: str = (
        "http://localhost:3000,http://127.0.0.1:3000"
    )
    ALLOWED_HOSTS: str = "*"
    API_DOCS_ENABLED: bool = True
    SECRET_KEY: str = DEVELOPMENT_SECRET_KEY
    ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 30
    REFRESH_TOKEN_EXPIRE_DAYS: int = 30
    PASSWORD_RESET_TOKEN_EXPIRE_MINUTES: int = 15
    PASSWORD_RESET_EXPOSE_TOKEN: bool = False
    SMTP_HOST: str | None = None
    SMTP_PORT: int = 587
    SMTP_USERNAME: str | None = None
    SMTP_PASSWORD: str | None = None
    SMTP_FROM_EMAIL: str | None = None
    SMTP_FROM_NAME: str = "EcoScan"
    SMTP_USE_TLS: bool = True
    SMTP_USE_SSL: bool = False
    IMAGE_RETENTION_DAYS: int = 90

    @property
    def database_url(self) -> str:
        """Return Render's PostgreSQL URL with the installed psycopg driver."""
        value = self.DATABASE_URL.strip()
        for prefix in ("postgresql://", "postgres://"):
            if value.startswith(prefix):
                return "postgresql+psycopg://" + value[len(prefix) :]
        return value

    @property
    def public_base_url(self) -> str:
        if (
            self.RENDER_EXTERNAL_HOSTNAME
            and self.PUBLIC_BASE_URL == DEFAULT_PUBLIC_BASE_URL
        ):
            return f"https://{self.RENDER_EXTERNAL_HOSTNAME}"
        return self.PUBLIC_BASE_URL

    @property
    def cors_allowed_origins(self) -> list[str]:
        return self._split_csv(self.CORS_ALLOWED_ORIGINS)

    @property
    def allowed_hosts(self) -> list[str]:
        if self.RENDER_EXTERNAL_HOSTNAME and self.ALLOWED_HOSTS == "*":
            return [self.RENDER_EXTERNAL_HOSTNAME]
        return self._split_csv(self.ALLOWED_HOSTS)

    def validate_production(self) -> None:
        if self.ENVIRONMENT != "production":
            return

        errors: list[str] = []
        public_url = urlparse(self.public_base_url)
        if public_url.scheme != "https" or not public_url.netloc:
            errors.append("PUBLIC_BASE_URL deve usar HTTPS em producao.")
        if (
            self.SECRET_KEY == DEVELOPMENT_SECRET_KEY
            or len(self.SECRET_KEY) < 64
        ):
            errors.append(
                "SECRET_KEY deve ser aleatoria e ter ao menos 64 caracteres."
            )
        if "postgresPassword" in self.database_url:
            errors.append("DATABASE_URL ainda usa a senha de desenvolvimento.")
        if self.PASSWORD_RESET_EXPOSE_TOKEN:
            errors.append(
                "PASSWORD_RESET_EXPOSE_TOKEN deve ser false em producao."
            )
        if not self.allowed_hosts or "*" in self.allowed_hosts:
            errors.append("ALLOWED_HOSTS deve listar hosts explicitos.")
        for origin in self.cors_allowed_origins:
            parsed_origin = urlparse(origin)
            if origin == "*" or parsed_origin.scheme != "https":
                errors.append(
                    "CORS_ALLOWED_ORIGINS deve conter somente origens HTTPS."
                )
                break

        if errors:
            raise ValueError(" ".join(errors))

    @staticmethod
    def _split_csv(value: str) -> list[str]:
        return [item.strip() for item in value.split(",") if item.strip()]
