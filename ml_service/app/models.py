from pathlib import Path
import json
import os
import tempfile

import joblib


def load_production(root: Path, academy_key: str, model_name: str):
    folder = root / academy_key / model_name
    pointer = folder / "production.json"
    if not pointer.is_file():
        return None
    version = json.loads(pointer.read_text(encoding="utf-8"))["version"]
    directory = folder / version
    metadata = json.loads((directory / "metadata.json").read_text(encoding="utf-8"))
    return joblib.load(directory / "pipeline.joblib"), metadata


def pointer_path(root: Path, academy_key: str, model_name: str) -> Path:
    return root / academy_key / model_name / "production.json"


def read_pointer(root: Path, academy_key: str, model_name: str) -> str | None:
    """Currently active model version, or None if nothing is promoted."""
    path = pointer_path(root, academy_key, model_name)
    if not path.is_file():
        return None
    try:
        return json.loads(path.read_text(encoding="utf-8")).get("version")
    except Exception:
        return None


def write_pointer(root: Path, academy_key: str, model_name: str, version: str) -> None:
    """Atomically point production at ``version``."""
    path = pointer_path(root, academy_key, model_name)
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=path.parent, suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            json.dump({"version": version}, stream)
        os.replace(tmp, path)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)


def restore_pointer(root: Path, academy_key: str, model_name: str,
                    version: str | None) -> None:
    """Restore the pointer to a prior state: re-point to ``version`` or, when
    there was none, remove the pointer entirely (used to undo an activation
    whose remote persistence failed)."""
    if version is None:
        pointer_path(root, academy_key, model_name).unlink(missing_ok=True)
    else:
        write_pointer(root, academy_key, model_name, version)
