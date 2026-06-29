from __future__ import annotations

import hashlib
import os
import sys
import tempfile
from pathlib import Path
from urllib.parse import urlparse
from urllib.request import urlopen


MAX_MODEL_BYTES = 250 * 1024 * 1024
DOWNLOAD_CHUNK_BYTES = 1024 * 1024


def _expected_sha256() -> str | None:
    value = os.getenv("ECOSCAN_MODEL_SHA256", "").strip().lower()
    if not value:
        return None
    if len(value) != 64 or any(character not in "0123456789abcdef" for character in value):
        raise RuntimeError("ECOSCAN_MODEL_SHA256 deve ser um SHA-256 hexadecimal.")
    return value


def _file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as model_file:
        for chunk in iter(lambda: model_file.read(DOWNLOAD_CHUNK_BYTES), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _validate_existing_model(path: Path, expected_sha256: str | None) -> None:
    if path.stat().st_size == 0:
        raise RuntimeError(f"O modelo em {path} esta vazio.")
    if expected_sha256 and _file_sha256(path) != expected_sha256:
        raise RuntimeError(f"O SHA-256 do modelo em {path} nao confere.")


def ensure_model() -> Path:
    default_path = Path(__file__).with_name("best.pt")
    model_path = Path(os.getenv("ECOSCAN_MODEL_PATH", str(default_path)))
    expected_sha256 = _expected_sha256()

    if model_path.is_file():
        _validate_existing_model(model_path, expected_sha256)
        return model_path

    model_url = os.getenv("ECOSCAN_MODEL_URL", "").strip()
    if not model_url:
        raise RuntimeError(
            "Modelo ausente. Defina ECOSCAN_MODEL_URL ou disponibilize "
            f"o arquivo em {model_path}."
        )
    if urlparse(model_url).scheme.lower() != "https":
        raise RuntimeError("ECOSCAN_MODEL_URL deve usar HTTPS.")

    model_path.parent.mkdir(parents=True, exist_ok=True)
    temporary_path: Path | None = None
    try:
        with urlopen(model_url, timeout=180) as response:  # noqa: S310
            final_url = response.geturl()
            if urlparse(final_url).scheme.lower() != "https":
                raise RuntimeError("O download do modelo redirecionou para uma URL insegura.")

            content_length = response.headers.get("Content-Length")
            if content_length and int(content_length) > MAX_MODEL_BYTES:
                raise RuntimeError("O modelo excede o limite de 250 MB.")

            digest = hashlib.sha256()
            downloaded_bytes = 0
            with tempfile.NamedTemporaryFile(
                mode="wb",
                prefix=f".{model_path.name}.",
                suffix=".part",
                dir=model_path.parent,
                delete=False,
            ) as temporary_file:
                temporary_path = Path(temporary_file.name)
                while chunk := response.read(DOWNLOAD_CHUNK_BYTES):
                    downloaded_bytes += len(chunk)
                    if downloaded_bytes > MAX_MODEL_BYTES:
                        raise RuntimeError("O modelo excede o limite de 250 MB.")
                    digest.update(chunk)
                    temporary_file.write(chunk)

        if downloaded_bytes == 0:
            raise RuntimeError("O download do modelo retornou um arquivo vazio.")
        if expected_sha256 and digest.hexdigest() != expected_sha256:
            raise RuntimeError("O SHA-256 do modelo baixado nao confere.")

        temporary_path.replace(model_path)
        temporary_path = None
        return model_path
    finally:
        if temporary_path is not None:
            temporary_path.unlink(missing_ok=True)


def server_command() -> list[str]:
    port = int(os.getenv("PORT", "8000"))
    if not 1 <= port <= 65535:
        raise RuntimeError("PORT deve estar entre 1 e 65535.")
    return [
        "uvicorn",
        "ecoscan.app:app",
        "--host",
        "0.0.0.0",
        "--port",
        str(port),
        "--proxy-headers",
        "--forwarded-allow-ips=*",
    ]


def main() -> None:
    try:
        model_path = ensure_model()
        os.environ["ECOSCAN_MODEL_PATH"] = str(model_path)
        command = server_command()
    except (OSError, RuntimeError, ValueError) as exc:
        print(f"Falha ao preparar a API: {exc}", file=sys.stderr)
        raise SystemExit(1) from exc

    os.execvp(command[0], command)


if __name__ == "__main__":
    main()
