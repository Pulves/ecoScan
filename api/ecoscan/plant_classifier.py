from __future__ import annotations

import json
import os
import threading
from io import BytesIO
from pathlib import Path
from typing import Any, Mapping


class InvalidImageError(ValueError):
    """Raised when the uploaded file is not a usable image."""


class ClassificationError(RuntimeError):
    """Raised when the model cannot produce a classification."""


class PlantClassifier:
    def __init__(
        self,
        model_path: Path,
        *,
        metadata_path: Path | None = None,
        device: str = "cpu",
        model: Any | None = None,
        metadata: Mapping[str, Any] | None = None,
    ) -> None:
        self.model_path = model_path.expanduser().resolve()
        self.metadata_path = (
            metadata_path.expanduser().resolve()
            if metadata_path is not None
            else self.model_path.with_name("model_metadata.json")
        )
        self.device = device
        self._model = model
        self._inference_lock = threading.Lock()
        self._metadata = (
            dict(metadata) if metadata is not None else self._read_metadata()
        )

    @classmethod
    def from_environment(cls) -> PlantClassifier:
        default_model_path = Path(__file__).resolve().parent / "best.pt"
        model_path = Path(
            os.getenv("ECOSCAN_MODEL_PATH", str(default_model_path))
        )

        metadata_value = os.getenv("ECOSCAN_METADATA_PATH")
        metadata_path = Path(metadata_value) if metadata_value else None

        return cls(
            model_path=model_path,
            metadata_path=metadata_path,
            device=os.getenv("ECOSCAN_DEVICE", "cpu"),
        )

    @property
    def ready(self) -> bool:
        return self._model is not None

    @property
    def image_size(self) -> int:
        return int(self._metadata.get("image_size", 224))

    def load(self) -> None:
        if self.ready:
            return

        if not self.model_path.is_file():
            raise FileNotFoundError(
                f"Modelo nao encontrado em: {self.model_path}. "
                "Copie o best.pt para esse local ou defina ECOSCAN_MODEL_PATH."
            )

        try:
            from ultralytics import YOLO
        except ImportError as exc:
            raise RuntimeError(
                "Ultralytics nao esta instalado. Execute "
                "'pip install -r ecoscan/requirements.txt'."
            ) from exc

        self._model = YOLO(str(self.model_path))

    def predict(
        self,
        image_bytes: bytes,
        *,
        confidence_threshold: float = 0.60,
        top_k: int = 3,
    ) -> dict[str, Any]:
        image = self._decode_image(image_bytes)
        return self.classify_image(
            image,
            confidence_threshold=confidence_threshold,
            top_k=top_k,
        )

    def classify_image(
        self,
        image: Any,
        *,
        confidence_threshold: float = 0.60,
        top_k: int = 3,
    ) -> dict[str, Any]:
        if not self.ready:
            raise ClassificationError("O modelo ainda nao foi carregado.")

        try:
            with self._inference_lock:
                results = self._model.predict(
                    source=image,
                    imgsz=self.image_size,
                    device=self.device,
                    verbose=False,
                )
        except Exception as exc:
            raise ClassificationError(
                "Falha ao executar o modelo de classificacao."
            ) from exc

        if not results:
            raise ClassificationError("O modelo nao retornou resultados.")

        return self._serialize_result(
            results[0],
            confidence_threshold=confidence_threshold,
            top_k=top_k,
        )

    def _decode_image(self, image_bytes: bytes) -> Any:
        if not image_bytes:
            raise InvalidImageError("A imagem enviada esta vazia.")

        try:
            from PIL import Image, ImageOps, UnidentifiedImageError
        except ImportError as exc:
            raise RuntimeError(
                "Pillow nao esta instalado. Execute "
                "'pip install -r ecoscan/requirements.txt'."
            ) from exc

        try:
            with Image.open(BytesIO(image_bytes)) as source:
                source.load()
                if source.width * source.height > 25_000_000:
                    raise InvalidImageError(
                        "A imagem excede o limite de 25 megapixels."
                    )
                return ImageOps.exif_transpose(source).convert("RGB")
        except InvalidImageError:
            raise
        except (UnidentifiedImageError, OSError, ValueError) as exc:
            raise InvalidImageError(
                "O arquivo enviado nao e uma imagem valida."
            ) from exc

    def _serialize_result(
        self,
        result: Any,
        *,
        confidence_threshold: float,
        top_k: int,
    ) -> dict[str, Any]:
        probabilities = getattr(result, "probs", None)
        if probabilities is None:
            raise ClassificationError(
                "O best.pt nao retornou probabilidades de classificacao. "
                "Verifique se ele foi treinado com a tarefa classify."
            )

        raw_scores = probabilities.data
        if hasattr(raw_scores, "detach"):
            raw_scores = raw_scores.detach().cpu()
        if hasattr(raw_scores, "tolist"):
            raw_scores = raw_scores.tolist()

        scores = [float(score) for score in raw_scores]
        if not scores:
            raise ClassificationError("O modelo retornou uma lista vazia.")

        names = getattr(result, "names", {})
        ranked_ids = sorted(
            range(len(scores)),
            key=scores.__getitem__,
            reverse=True,
        )[: min(top_k, len(scores))]

        alternatives = []
        display_names = self._metadata.get("display_names_pt_br", {})
        for class_id in ranked_ids:
            slug = self._class_name(names, class_id)
            alternatives.append(
                {
                    "class_id": class_id,
                    "slug": slug,
                    "name": display_names.get(slug, self._display_name(slug)),
                    "confidence": round(scores[class_id], 6),
                }
            )

        top_prediction = alternatives[0]
        recognized = top_prediction["confidence"] >= confidence_threshold

        return {
            "success": True,
            "recognized": recognized,
            "plant": top_prediction if recognized else None,
            "alternatives": alternatives,
            "threshold": confidence_threshold,
            "model": {
                "task": "classification",
                "architecture": self._metadata.get(
                    "architecture", self.model_path.name
                ),
                "image_size": self.image_size,
            },
        }

    def _read_metadata(self) -> dict[str, Any]:
        if not self.metadata_path.is_file():
            return {}

        try:
            with self.metadata_path.open(encoding="utf-8") as file:
                metadata = json.load(file)
        except (OSError, json.JSONDecodeError) as exc:
            raise RuntimeError(
                f"Nao foi possivel ler os metadados: {self.metadata_path}"
            ) from exc

        if not isinstance(metadata, dict):
            raise RuntimeError("model_metadata.json deve conter um objeto JSON.")
        return metadata

    @staticmethod
    def _class_name(names: Any, class_id: int) -> str:
        if isinstance(names, Mapping):
            value = names.get(class_id, names.get(str(class_id), class_id))
        else:
            try:
                value = names[class_id]
            except (IndexError, KeyError, TypeError):
                value = class_id
        return str(value)

    @staticmethod
    def _display_name(slug: str) -> str:
        return slug.replace("_", " ").replace("-", " ").strip().title()
