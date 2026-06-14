from pathlib import Path
from unittest import TestCase

from ecoscan.plant_classifier import ClassificationError, PlantClassifier


class FakeProbabilities:
    data = [0.1, 0.75, 0.15]


class FakeResult:
    probs = FakeProbabilities()
    names = {0: "banana", 1: "mango", 2: "tomato"}


class FakeModel:
    def __init__(self) -> None:
        self.calls = []

    def predict(self, **kwargs):
        self.calls.append(kwargs)
        return [FakeResult()]


class EmptyModel:
    def predict(self, **kwargs):
        return []


class PlantClassifierTests(TestCase):
    def test_returns_recognized_plant_and_ranked_alternatives(self) -> None:
        model = FakeModel()
        classifier = PlantClassifier(
            Path("best.pt"),
            device="cpu",
            model=model,
            metadata={
                "architecture": "yolo11s-cls.pt",
                "image_size": 224,
                "display_names_pt_br": {"mango": "Manga"},
            },
        )

        response = classifier.classify_image(
            object(),
            confidence_threshold=0.60,
            top_k=2,
        )

        self.assertTrue(response["recognized"])
        self.assertEqual(response["plant"]["slug"], "mango")
        self.assertEqual(response["plant"]["name"], "Manga")
        self.assertEqual(
            [item["slug"] for item in response["alternatives"]],
            ["mango", "tomato"],
        )
        self.assertEqual(model.calls[0]["imgsz"], 224)
        self.assertEqual(model.calls[0]["device"], "cpu")

    def test_rejects_prediction_below_threshold(self) -> None:
        classifier = PlantClassifier(
            Path("best.pt"),
            model=FakeModel(),
            metadata={},
        )

        response = classifier.classify_image(
            object(),
            confidence_threshold=0.90,
            top_k=3,
        )

        self.assertFalse(response["recognized"])
        self.assertIsNone(response["plant"])
        self.assertEqual(response["alternatives"][0]["name"], "Mango")

    def test_raises_when_model_returns_no_results(self) -> None:
        classifier = PlantClassifier(
            Path("best.pt"),
            model=EmptyModel(),
            metadata={},
        )

        with self.assertRaises(ClassificationError):
            classifier.classify_image(object())
