# %% [markdown]
# # EcoScan - treinamento YOLO11 para classificacao de plantas
#
# Este notebook prepara o dataset "Plant Classification", treina um
# `yolo11s-cls.pt` e publica `/kaggle/working/best.pt`.
#
# O problema e de classificacao: cada foto deve conter uma planta principal e
# recebe uma unica classe. Bounding boxes nao sao necessarias.

# %% [markdown]
# ## 1. Instalar a biblioteca
#
# No Kaggle, habilite uma GPU e o acesso a internet antes de executar. O acesso
# tambem sera necessario para baixar `yolo11s-cls.pt` na primeira execucao.

# %%
from importlib.metadata import PackageNotFoundError, version
from pathlib import Path
import subprocess
import sys

from packaging.version import Version

ULTRALYTICS_REQUIREMENT = "ultralytics>=8.3.0,<9.0"


def installed_ultralytics_version() -> str | None:
    try:
        return version("ultralytics")
    except PackageNotFoundError:
        return None


installed_version = installed_ultralytics_version()
compatible_version = (
    installed_version is not None
    and Version("8.3.0") <= Version(installed_version) < Version("9.0.0")
)

if compatible_version:
    print(f"Ultralytics {installed_version} ja esta instalado.")
else:
    # Permite usar um wheel anexado como dataset quando a internet do Kaggle
    # nao puder ser habilitada.
    wheel_candidates = sorted(
        Path("/kaggle/input").rglob("ultralytics-*.whl")
    )
    install_target = (
        str(wheel_candidates[-1])
        if wheel_candidates
        else ULTRALYTICS_REQUIREMENT
    )

    if installed_version:
        print(
            f"Ultralytics {installed_version} e incompativel; "
            f"instalando {install_target}."
        )
    else:
        print(f"Ultralytics nao encontrado; instalando {install_target}.")

    command = [
        sys.executable,
        "-m",
        "pip",
        "install",
        "--no-cache-dir",
        install_target,
    ]
    completed = subprocess.run(
        command,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    print(completed.stdout)

    if completed.returncode != 0:
        raise RuntimeError(
            "Nao foi possivel instalar o Ultralytics. No Kaggle, abra "
            "'Notebook options' ou 'Settings', ative 'Internet' e execute "
            "esta celula novamente. Se a opcao de internet nao estiver "
            "disponivel, anexe ao notebook um dataset contendo o arquivo "
            "ultralytics-*.whl. A saida completa do pip aparece acima."
        )

    print(f"Ultralytics {installed_ultralytics_version()} instalado com sucesso.")

# %% [markdown]
# ## 2. Configuracao
#
# Edite somente `SELECTED_PLANTS` para escolher de duas a cinco classes.
# Se a descoberta automatica encontrar mais de uma copia do dataset, informe
# `SOURCE_ROOT`, por exemplo:
# `/kaggle/input/plant-classification/Plant Classification`.

# %%
import hashlib
import json
import platform
import random
import shutil
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import matplotlib.pyplot as plt
import pandas as pd
import torch
import ultralytics
from IPython.display import display
from PIL import Image, ImageOps
from ultralytics import YOLO

INPUT_ROOT = Path("/kaggle/input")
WORK_ROOT = Path("/kaggle/working")

# Use None para descoberta automatica.
SOURCE_ROOT: Path | None = None

# Selecione entre 2 e 5 plantas antes do treinamento.
SELECTED_PLANTS = [
    "Coffe-plant",
    "banana",
    "coconut",
    "mango",
    "tomato",
]

# O nome da pasta de destino vira o rotulo armazenado dentro do best.pt.
MODEL_CLASS_NAMES = {
    "Coffe-plant": "coffee",
    "banana": "banana",
    "coconut": "coconut",
    "mango": "mango",
    "tomato": "tomato",
}

DISPLAY_NAMES_PT_BR = {
    "coffee": "Cafe",
    "banana": "Bananeira",
    "coconut": "Coqueiro",
    "mango": "Mangueira",
    "tomato": "Tomateiro",
}

# Aceita pequenas variacoes no nome da pasta original.
SOURCE_ALIASES = {
    "Coffe-plant": {"coffeplant", "coffeeplant", "coffee"},
    "banana": {"banana", "bananaplant"},
    "coconut": {"coconut", "coconutplant"},
    "mango": {"mango", "mangoplant"},
    "tomato": {"tomato", "tomatoplant"},
}

SEED = 42
TRAIN_RATIO = 0.70
VAL_RATIO = 0.15
TEST_RATIO = 0.15

MODEL_CHECKPOINT = "yolo11s-cls.pt"
IMAGE_SIZE = 224
EPOCHS = 80
BATCH_SIZE = 32
PATIENCE = 15
MIN_IMAGES_PER_CLASS = 20

DATASET_ROOT = WORK_ROOT / "plant_classification_yolo"
RUNS_ROOT = WORK_ROOT / "ecoscan_runs"
RUN_NAME = "yolo11s_plant_classifier"
ARTIFACTS_ROOT = WORK_ROOT / "ecoscan_model"
BEST_PT = WORK_ROOT / "best.pt"

SUPPORTED_EXTENSIONS = {
    ".jpg",
    ".jpeg",
    ".png",
    ".bmp",
    ".webp",
    ".tif",
    ".tiff",
}

assert 2 <= len(SELECTED_PLANTS) <= 5, (
    "Selecione entre 2 e 5 plantas em SELECTED_PLANTS."
)
assert len(SELECTED_PLANTS) == len(set(SELECTED_PLANTS)), (
    "SELECTED_PLANTS nao pode conter nomes repetidos."
)
assert abs(TRAIN_RATIO + VAL_RATIO + TEST_RATIO - 1.0) < 1e-9
assert set(SELECTED_PLANTS).issubset(MODEL_CLASS_NAMES), (
    "Existe uma planta selecionada sem nome de classe configurado."
)

random.seed(SEED)
DEVICE: int | str = 0 if torch.cuda.is_available() else "cpu"

print(f"Python: {platform.python_version()}")
print(f"PyTorch: {torch.__version__}")
print(f"GPU disponivel: {torch.cuda.is_available()}")
if torch.cuda.is_available():
    print(f"GPU: {torch.cuda.get_device_name(0)}")
else:
    print("AVISO: o treinamento em CPU sera muito mais lento.")
print(f"Classes selecionadas: {SELECTED_PLANTS}")

# %% [markdown]
# ## 3. Localizar as pastas das classes
#
# A busca agrupa pastas irmas para evitar misturar classes de datasets
# diferentes que estejam anexados ao mesmo notebook.

# %%
def normalize_name(value: str) -> str:
    return "".join(character for character in value.casefold() if character.isalnum())


def count_candidate_images(directory: Path) -> int:
    return sum(
        1
        for path in directory.rglob("*")
        if path.is_file() and path.suffix.casefold() in SUPPORTED_EXTENSIONS
    )


def find_class_directories(
    search_root: Path,
    selected_plants: list[str],
) -> tuple[Path, dict[str, Path]]:
    if not search_root.exists():
        raise FileNotFoundError(
            f"Diretorio de entrada nao encontrado: {search_root}. "
            "Anexe o dataset ao notebook Kaggle."
        )

    alias_to_source: dict[str, str] = {}
    for source_name in selected_plants:
        aliases = SOURCE_ALIASES[source_name] | {normalize_name(source_name)}
        for alias in aliases:
            alias_to_source[normalize_name(alias)] = source_name

    candidates_by_parent: dict[Path, dict[str, list[Path]]] = defaultdict(
        lambda: defaultdict(list)
    )

    directories = [search_root]
    directories.extend(path for path in search_root.rglob("*") if path.is_dir())

    for directory in directories:
        source_name = alias_to_source.get(normalize_name(directory.name))
        if source_name:
            candidates_by_parent[directory.parent][source_name].append(directory)

    ranked_groups: list[tuple[int, int, str, Path, dict[str, list[Path]]]] = []
    for parent, grouped_candidates in candidates_by_parent.items():
        matched_classes = len(grouped_candidates)
        image_count = sum(
            count_candidate_images(candidate)
            for candidates in grouped_candidates.values()
            for candidate in candidates
        )
        ranked_groups.append(
            (
                matched_classes,
                image_count,
                str(parent),
                parent,
                grouped_candidates,
            )
        )

    if not ranked_groups:
        raise FileNotFoundError(
            "Nenhuma pasta de classe foi encontrada. Defina SOURCE_ROOT com o "
            "caminho exato do dataset."
        )

    _, _, _, dataset_parent, best_group = max(ranked_groups)
    missing = [name for name in selected_plants if name not in best_group]
    if missing:
        found = sorted(best_group)
        raise FileNotFoundError(
            f"Classes ausentes em {dataset_parent}: {missing}. "
            f"Classes encontradas: {found}. Ajuste SOURCE_ROOT ou os aliases."
        )

    resolved: dict[str, Path] = {}
    for source_name in selected_plants:
        resolved[source_name] = max(
            best_group[source_name],
            key=count_candidate_images,
        )

    return dataset_parent, resolved


search_root = SOURCE_ROOT if SOURCE_ROOT is not None else INPUT_ROOT
detected_dataset_root, source_class_dirs = find_class_directories(
    Path(search_root),
    SELECTED_PLANTS,
)

print(f"Dataset localizado em: {detected_dataset_root}")
for source_name, directory in source_class_dirs.items():
    print(
        f"- {source_name}: {directory} "
        f"({count_candidate_images(directory)} arquivos candidatos)"
    )

# %% [markdown]
# ## 4. Validar, deduplicar e dividir o dataset
#
# A divisao e feita por classe, com semente fixa:
#
# - 70% treino
# - 15% validacao
# - 15% teste
#
# Imagens corrompidas sao ignoradas. Duplicatas exatas sao removidas antes da
# divisao, evitando que a mesma imagem apareca no treino e no teste.

# %%
def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as file:
        for block in iter(lambda: file.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def validate_image(path: Path) -> tuple[bool, str | None]:
    try:
        with Image.open(path) as image:
            image.verify()
        return True, None
    except Exception as error:
        return False, f"{type(error).__name__}: {error}"


def split_sizes(total: int) -> dict[str, int]:
    test_count = max(1, round(total * TEST_RATIO))
    val_count = max(1, round(total * VAL_RATIO))
    train_count = total - val_count - test_count
    if train_count < 1:
        raise ValueError(f"Quantidade insuficiente para dividir {total} imagens.")
    return {"train": train_count, "val": val_count, "test": test_count}


def save_as_rgb_jpeg(source: Path, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    with Image.open(source) as image:
        image = ImageOps.exif_transpose(image).convert("RGB")
        image.save(destination, format="JPEG", quality=95, optimize=True)


if DATASET_ROOT.exists():
    shutil.rmtree(DATASET_ROOT)
DATASET_ROOT.mkdir(parents=True)

manifest_rows: list[dict[str, Any]] = []
summary_rows: list[dict[str, Any]] = []
rejected_rows: list[dict[str, str]] = []
global_hashes: dict[str, tuple[str, Path]] = {}

for class_position, source_name in enumerate(SELECTED_PLANTS):
    model_class_name = MODEL_CLASS_NAMES[source_name]
    candidates = sorted(
        path
        for path in source_class_dirs[source_name].rglob("*")
        if path.is_file() and path.suffix.casefold() in SUPPORTED_EXTENSIONS
    )

    valid_unique: list[tuple[Path, str]] = []
    corrupt_count = 0
    duplicate_count = 0

    for candidate in candidates:
        is_valid, error = validate_image(candidate)
        if not is_valid:
            corrupt_count += 1
            rejected_rows.append(
                {
                    "source_class": source_name,
                    "path": str(candidate),
                    "reason": error or "invalid_image",
                }
            )
            continue

        file_hash = sha256_file(candidate)
        if file_hash in global_hashes:
            duplicate_count += 1
            first_class, first_path = global_hashes[file_hash]
            rejected_rows.append(
                {
                    "source_class": source_name,
                    "path": str(candidate),
                    "reason": (
                        f"duplicate_of={first_path}; "
                        f"original_class={first_class}"
                    ),
                }
            )
            continue

        global_hashes[file_hash] = (source_name, candidate)
        valid_unique.append((candidate, file_hash))

    if len(valid_unique) < MIN_IMAGES_PER_CLASS:
        raise ValueError(
            f"A classe {source_name!r} possui somente {len(valid_unique)} "
            f"imagens validas e unicas; o minimo configurado e "
            f"{MIN_IMAGES_PER_CLASS}."
        )

    class_rng = random.Random(SEED + class_position)
    class_rng.shuffle(valid_unique)
    sizes = split_sizes(len(valid_unique))

    split_items = {
        "train": valid_unique[: sizes["train"]],
        "val": valid_unique[
            sizes["train"] : sizes["train"] + sizes["val"]
        ],
        "test": valid_unique[sizes["train"] + sizes["val"] :],
    }

    for split_name, items in split_items.items():
        for index, (source_path, file_hash) in enumerate(items):
            destination = (
                DATASET_ROOT
                / split_name
                / model_class_name
                / f"{model_class_name}_{index:04d}_{file_hash[:10]}.jpg"
            )
            save_as_rgb_jpeg(source_path, destination)
            manifest_rows.append(
                {
                    "split": split_name,
                    "source_class": source_name,
                    "model_class": model_class_name,
                    "sha256": file_hash,
                    "source_path": str(source_path),
                    "dataset_path": str(destination),
                }
            )

    summary_rows.append(
        {
            "source_class": source_name,
            "model_class": model_class_name,
            "candidates": len(candidates),
            "valid_unique": len(valid_unique),
            "corrupt": corrupt_count,
            "duplicates": duplicate_count,
            **sizes,
        }
    )

manifest_df = pd.DataFrame(manifest_rows)
summary_df = pd.DataFrame(summary_rows)
rejected_df = pd.DataFrame(rejected_rows)

manifest_df.to_csv(DATASET_ROOT / "split_manifest.csv", index=False)
summary_df.to_csv(DATASET_ROOT / "dataset_summary.csv", index=False)
rejected_df.to_csv(DATASET_ROOT / "rejected_images.csv", index=False)

print(f"Dataset YOLO criado em: {DATASET_ROOT}")
display(summary_df)

# %% [markdown]
# ## 5. Inspecao visual
#
# Verifique se as imagens e os rotulos estao corretos antes de treinar.

# %%
sample_rows = (
    manifest_df[manifest_df["split"] == "train"]
    .groupby("model_class", group_keys=False)
    .sample(n=1, random_state=SEED)
    .reset_index(drop=True)
)

figure, axes = plt.subplots(
    1,
    len(sample_rows),
    figsize=(4 * len(sample_rows), 4),
)
if len(sample_rows) == 1:
    axes = [axes]

for axis, (_, row) in zip(axes, sample_rows.iterrows()):
    with Image.open(row["dataset_path"]) as image:
        axis.imshow(image)
    axis.set_title(row["model_class"])
    axis.axis("off")

plt.tight_layout()
plt.show()

# %% [markdown]
# ## 6. Treinar o YOLO11s para classificacao
#
# `yolo11s-cls.pt` oferece um bom equilibrio para este conjunto pequeno:
# capacidade superior ao modelo nano, inferencia ainda leve para uma API e
# risco menor de sobreajuste do que as variantes medium/large/xlarge.

# %%
model = YOLO(MODEL_CHECKPOINT)

train_results = model.train(
    data=str(DATASET_ROOT),
    epochs=EPOCHS,
    imgsz=IMAGE_SIZE,
    batch=BATCH_SIZE,
    patience=PATIENCE,
    device=DEVICE,
    workers=4,
    project=str(RUNS_ROOT),
    name=RUN_NAME,
    exist_ok=True,
    pretrained=True,
    optimizer="AdamW",
    lr0=0.001,
    lrf=0.01,
    weight_decay=0.0005,
    dropout=0.20,
    warmup_epochs=3,
    cos_lr=True,
    amp=True,
    cache="disk",
    seed=SEED,
    deterministic=True,
    degrees=10.0,
    translate=0.10,
    scale=0.20,
    shear=2.0,
    perspective=0.0005,
    fliplr=0.50,
    flipud=0.05,
    hsv_h=0.015,
    hsv_s=0.40,
    hsv_v=0.30,
    auto_augment="randaugment",
    erasing=0.20,
    plots=True,
    verbose=True,
)

RUN_DIR = Path(model.trainer.save_dir)
TRAINED_BEST_PT = RUN_DIR / "weights" / "best.pt"
TRAINED_LAST_PT = RUN_DIR / "weights" / "last.pt"

if not TRAINED_BEST_PT.exists():
    raise FileNotFoundError(f"best.pt nao foi gerado em {TRAINED_BEST_PT}")

print(f"Treinamento concluido: {RUN_DIR}")
print(f"Melhor peso: {TRAINED_BEST_PT}")

# %% [markdown]
# ## 7. Avaliar no conjunto de teste e publicar os artefatos

# %%
best_model = YOLO(str(TRAINED_BEST_PT))
test_metrics = best_model.val(
    data=str(DATASET_ROOT),
    split="test",
    imgsz=IMAGE_SIZE,
    batch=BATCH_SIZE,
    device=DEVICE,
    workers=4,
    project=str(RUNS_ROOT),
    name=f"{RUN_NAME}_test",
    exist_ok=True,
    plots=True,
)

if ARTIFACTS_ROOT.exists():
    shutil.rmtree(ARTIFACTS_ROOT)
ARTIFACTS_ROOT.mkdir(parents=True)

shutil.copy2(TRAINED_BEST_PT, BEST_PT)
shutil.copy2(TRAINED_BEST_PT, ARTIFACTS_ROOT / "best.pt")
shutil.copy2(DATASET_ROOT / "split_manifest.csv", ARTIFACTS_ROOT)
shutil.copy2(DATASET_ROOT / "dataset_summary.csv", ARTIFACTS_ROOT)
shutil.copy2(DATASET_ROOT / "rejected_images.csv", ARTIFACTS_ROOT)

for artifact_name in [
    "results.csv",
    "results.png",
    "confusion_matrix.png",
    "confusion_matrix_normalized.png",
]:
    source_artifact = RUN_DIR / artifact_name
    if source_artifact.exists():
        shutil.copy2(source_artifact, ARTIFACTS_ROOT / artifact_name)

class_names = {
    int(index): name for index, name in best_model.names.items()
}
metadata = {
    "model_file": "best.pt",
    "architecture": MODEL_CHECKPOINT,
    "task": "classify",
    "image_size": IMAGE_SIZE,
    "created_at_utc": datetime.now(timezone.utc).isoformat(),
    "selected_source_classes": SELECTED_PLANTS,
    "class_names_by_id": class_names,
    "display_names_pt_br": DISPLAY_NAMES_PT_BR,
    "split_ratios": {
        "train": TRAIN_RATIO,
        "val": VAL_RATIO,
        "test": TEST_RATIO,
    },
    "test_metrics": {
        "top1_accuracy": float(test_metrics.top1),
        "top5_accuracy": float(test_metrics.top5),
    },
    "versions": {
        "python": platform.python_version(),
        "torch": torch.__version__,
        "ultralytics": ultralytics.__version__,
    },
    "best_pt_sha256": sha256_file(BEST_PT),
}

with (ARTIFACTS_ROOT / "model_metadata.json").open(
    "w",
    encoding="utf-8",
) as file:
    json.dump(metadata, file, ensure_ascii=False, indent=2)

archive_path = shutil.make_archive(
    str(WORK_ROOT / "ecoscan_yolo11s_classifier"),
    "zip",
    root_dir=ARTIFACTS_ROOT,
)

print(f"Top-1 no teste: {test_metrics.top1:.4f}")
print(f"Top-5 no teste: {test_metrics.top5:.4f}")
print(f"Arquivo principal: {BEST_PT}")
print(f"Pacote completo: {archive_path}")
print(f"Tamanho do best.pt: {BEST_PT.stat().st_size / (1024 ** 2):.2f} MB")

# %% [markdown]
# ## 8. Testar o mesmo JSON que a API podera retornar
#
# Um classificador fechado sempre escolhe uma das classes conhecidas. O limiar
# abaixo ajuda a rejeitar previsoes fracas, mas a versao de producao melhora
# bastante se o treinamento incluir uma classe `unknown` com outras plantas,
# solo, maos, vasos e fundos comuns.

# %%
def prediction_to_api_json(
    image_path: str | Path,
    confidence_threshold: float = 0.60,
    top_k: int = 3,
) -> dict[str, Any]:
    result = best_model.predict(
        source=str(image_path),
        imgsz=IMAGE_SIZE,
        device=DEVICE,
        verbose=False,
    )[0]

    probabilities = result.probs
    if probabilities is None:
        raise RuntimeError("O modelo nao retornou probabilidades de classificacao.")

    ranked_ids = probabilities.top5[: min(top_k, len(result.names))]
    alternatives = [
        {
            "class_id": int(class_id),
            "slug": result.names[int(class_id)],
            "name": DISPLAY_NAMES_PT_BR.get(
                result.names[int(class_id)],
                result.names[int(class_id)],
            ),
            "confidence": round(
                float(probabilities.data[int(class_id)].item()),
                6,
            ),
        }
        for class_id in ranked_ids
    ]

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
            "architecture": MODEL_CHECKPOINT,
            "image_size": IMAGE_SIZE,
        },
    }


test_image = Path(manifest_df[manifest_df["split"] == "test"].iloc[0]["dataset_path"])
example_response = prediction_to_api_json(test_image)
print(json.dumps(example_response, ensure_ascii=False, indent=2))

# %% [markdown]
# ## 9. Download
#
# Na aba **Output** do notebook Kaggle, baixe:
#
# - `/kaggle/working/best.pt`: peso usado pela API Python.
# - `/kaggle/working/ecoscan_yolo11s_classifier.zip`: peso, metadados, manifesto
#   e graficos de treinamento.
