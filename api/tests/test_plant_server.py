from io import BytesIO
from pathlib import Path
from unittest import TestCase
from unittest.mock import patch

from fastapi.testclient import TestClient
from PIL import Image

from ecoscan import database
from ecoscan.plant_classifier import PlantClassifier
from ecoscan.plant_server import create_app
from ecoscan.settings import DEVELOPMENT_SECRET_KEY, Settings


def create_png_image() -> bytes:
    buffer = BytesIO()
    Image.new("RGB", (2, 2), color="green").save(buffer, format="PNG")
    return buffer.getvalue()


class FakeProbabilities:
    data = [0.82, 0.18]


class FakeResult:
    probs = FakeProbabilities()
    names = {0: "banana", 1: "mango"}


class FakeModel:
    def predict(self, **kwargs):
        return [FakeResult()]


class PlantServerTests(TestCase):
    def setUp(self) -> None:
        classifier = PlantClassifier(
            Path("best.pt"),
            model=FakeModel(),
            metadata={"display_names_pt_br": {"banana": "Bananeira"}},
        )
        self.client_context = TestClient(
            create_app(classifier, initialize_database=False)
        )
        self.client = self.client_context.__enter__()

    def tearDown(self) -> None:
        self.client_context.__exit__(None, None, None)

    def test_identifies_multipart_image(self) -> None:
        response = self.client.post(
            "/plants/identify",
            files={"image": ("plant.png", create_png_image(), "image/png")},
        )

        self.assertEqual(response.status_code, 200, response.text)
        body = response.json()
        self.assertTrue(body["recognized"])
        self.assertEqual(body["plant"]["name"], "Bananeira")
        self.assertEqual(len(body["alternatives"]), 2)

    def test_rejects_unsupported_media_type(self) -> None:
        response = self.client.post(
            "/plants/identify",
            files={"image": ("plant.txt", b"not an image", "text/plain")},
        )

        self.assertEqual(response.status_code, 415)

    def test_reports_loaded_model(self) -> None:
        response = self.client.get("/plants/health")

        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.json()["model_loaded"])

    def test_exposes_unified_service_information(self) -> None:
        response = self.client.get("/")

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["service"], "EcoScan API")
        self.assertEqual(response.json()["users"], "/users/")

    def test_cors_allows_only_configured_origin(self) -> None:
        classifier = PlantClassifier(
            Path("best.pt"),
            model=FakeModel(),
            metadata={},
        )
        settings = Settings(
            _env_file=None,
            CORS_ALLOWED_ORIGINS="https://app.example.com",
        )
        with TestClient(
            create_app(
                classifier,
                initialize_database=False,
                app_settings=settings,
            )
        ) as client:
            allowed = client.options(
                "/plants/health",
                headers={
                    "Origin": "https://app.example.com",
                    "Access-Control-Request-Method": "GET",
                },
            )
            denied = client.options(
                "/plants/health",
                headers={
                    "Origin": "https://evil.example.com",
                    "Access-Control-Request-Method": "GET",
                },
            )

        self.assertEqual(
            allowed.headers["access-control-allow-origin"],
            "https://app.example.com",
        )
        self.assertNotIn("access-control-allow-origin", denied.headers)

    def test_rejects_development_secrets_in_production(self) -> None:
        settings = Settings(
            _env_file=None,
            ENVIRONMENT="production",
            PUBLIC_BASE_URL="https://api.example.com",
            CORS_ALLOWED_ORIGINS="https://app.example.com",
            ALLOWED_HOSTS="api.example.com",
            SECRET_KEY=DEVELOPMENT_SECRET_KEY,
            DATABASE_URL=(
                "postgresql+psycopg://postgres:strong@db:5432/ecoscan"
            ),
        )

        with self.assertRaises(ValueError):
            settings.validate_production()

    def test_uses_render_environment_defaults_in_production(self) -> None:
        settings = Settings(
            _env_file=None,
            ENVIRONMENT="production",
            RENDER_EXTERNAL_HOSTNAME="ecoscan-api.onrender.com",
            CORS_ALLOWED_ORIGINS="",
            SECRET_KEY="s" * 64,
            DATABASE_URL=(
                "postgresql://ecoscan:strong@database.internal/ecoscan"
            ),
        )

        settings.validate_production()

        self.assertEqual(
            settings.database_url,
            "postgresql+psycopg://ecoscan:strong@database.internal/ecoscan",
        )
        self.assertEqual(
            settings.public_base_url,
            "https://ecoscan-api.onrender.com",
        )
        self.assertEqual(
            settings.allowed_hosts,
            ["ecoscan-api.onrender.com"],
        )

    def test_alembic_accepts_percent_encoded_database_password(self) -> None:
        database_url = (
            "postgresql://ecoscan:pass%2Fword@database.internal/ecoscan"
        )
        with patch.object(database.settings, "DATABASE_URL", database_url):
            config = database._alembic_config()

        self.assertEqual(
            config.get_main_option("sqlalchemy.url"),
            "postgresql+psycopg://ecoscan:pass%2Fword@database.internal/ecoscan",
        )


class PlantServerWithoutModelTests(TestCase):
    def test_starts_service_and_reports_missing_model(self) -> None:
        classifier = PlantClassifier(
            Path("missing-best.pt"),
            metadata={},
        )

        with TestClient(
            create_app(classifier, initialize_database=False)
        ) as client:
            health_response = client.get("/plants/health")
            identify_response = client.post(
                "/plants/identify",
                files={
                    "image": (
                        "plant.png",
                        create_png_image(),
                        "image/png",
                    )
                },
            )

        self.assertEqual(health_response.status_code, 200)
        self.assertFalse(health_response.json()["model_loaded"])
        self.assertEqual(health_response.json()["status"], "unavailable")
        self.assertEqual(identify_response.status_code, 503)
