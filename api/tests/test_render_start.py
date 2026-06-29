from __future__ import annotations

import hashlib
import os
import tempfile
from io import BytesIO
from pathlib import Path
from unittest import TestCase
from unittest.mock import patch

from ecoscan.render_start import ensure_model, server_command


class FakeResponse(BytesIO):
    def __init__(self, content: bytes, url: str) -> None:
        super().__init__(content)
        self.headers = {"Content-Length": str(len(content))}
        self._url = url

    def geturl(self) -> str:
        return self._url


class RenderStartTests(TestCase):
    def test_reuses_existing_model_with_matching_hash(self) -> None:
        content = b"model-content"
        with tempfile.TemporaryDirectory() as directory:
            model_path = Path(directory) / "best.pt"
            model_path.write_bytes(content)
            environment = {
                "ECOSCAN_MODEL_PATH": str(model_path),
                "ECOSCAN_MODEL_SHA256": hashlib.sha256(content).hexdigest(),
            }

            with patch.dict(os.environ, environment, clear=True):
                result = ensure_model()

        self.assertEqual(result, model_path)

    def test_downloads_model_and_checks_hash(self) -> None:
        content = b"downloaded-model"
        model_url = "https://example.com/best.pt"
        with tempfile.TemporaryDirectory() as directory:
            model_path = Path(directory) / "best.pt"
            environment = {
                "ECOSCAN_MODEL_PATH": str(model_path),
                "ECOSCAN_MODEL_URL": model_url,
                "ECOSCAN_MODEL_SHA256": hashlib.sha256(content).hexdigest(),
            }

            with (
                patch.dict(os.environ, environment, clear=True),
                patch(
                    "ecoscan.render_start.urlopen",
                    return_value=FakeResponse(content, model_url),
                ),
            ):
                result = ensure_model()

            self.assertEqual(result.read_bytes(), content)

    def test_rejects_non_https_model_url(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            environment = {
                "ECOSCAN_MODEL_PATH": str(Path(directory) / "best.pt"),
                "ECOSCAN_MODEL_URL": "http://example.com/best.pt",
            }
            with patch.dict(os.environ, environment, clear=True):
                with self.assertRaises(RuntimeError):
                    ensure_model()

    def test_uses_render_port(self) -> None:
        with patch.dict(os.environ, {"PORT": "10000"}, clear=True):
            command = server_command()

        self.assertEqual(command[command.index("--port") + 1], "10000")
