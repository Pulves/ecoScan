from io import BytesIO
from pathlib import Path
from unittest import TestCase

from fastapi.testclient import TestClient
from PIL import Image

from ecoscan.plant_classifier import PlantClassifier
from ecoscan.plant_server import create_app


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
        self.client_context = TestClient(create_app(classifier))
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
