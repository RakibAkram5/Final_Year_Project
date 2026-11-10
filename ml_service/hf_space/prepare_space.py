"""Assembles the files of the Hugging Face Space into ./build.

Usage (from the repository root):
    python ml_service/hf_space/prepare_space.py
    hf upload <hf-user>/<space-name> ml_service/hf_space/build . --repo-type space

Only the service code is copied: no tests, caches, artifacts or .env files.
"""
from pathlib import Path
import shutil

HERE = Path(__file__).resolve().parent
SERVICE = HERE.parent
BUILD = HERE / "build"


def main() -> None:
    if BUILD.exists():
        shutil.rmtree(BUILD)
    BUILD.mkdir()
    shutil.copy2(HERE / "Dockerfile", BUILD / "Dockerfile")
    shutil.copy2(HERE / "README.md", BUILD / "README.md")
    shutil.copy2(SERVICE / "requirements.txt", BUILD / "requirements.txt")
    shutil.copytree(SERVICE / "app", BUILD / "app",
                    ignore=shutil.ignore_patterns("__pycache__", "*.pyc", ".env*"))
    files = sorted(p.relative_to(BUILD).as_posix() for p in BUILD.rglob("*") if p.is_file())
    print(f"Prepared {len(files)} files in {BUILD}:")
    for name in files:
        print("  ", name)


if __name__ == "__main__":
    main()
