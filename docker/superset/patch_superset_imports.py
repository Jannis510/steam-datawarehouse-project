import os
import sys
import zipfile
from pathlib import Path


def _patched_yaml(text: str, uri: str, force: bool) -> str:
    mask_tokens = ("XXXXXXXXXX", "REDACTED", "***")
    changed = False
    lines = []
    for line in text.splitlines():
        if line.startswith("sqlalchemy_uri:"):
            if force or any(token in line for token in mask_tokens):
                line = f"sqlalchemy_uri: {uri}"
                changed = True
        lines.append(line)
    if not changed:
        return text
    return "\n".join(lines) + ("\n" if text.endswith("\n") else "")


def patch_imports(src_dir: Path, dst_dir: Path, uri: str, force: bool) -> None:
    dst_dir.mkdir(parents=True, exist_ok=True)
    for zip_path in src_dir.glob("*.zip"):
        with zipfile.ZipFile(zip_path) as src_zip:
            out_path = dst_dir / zip_path.name
            with zipfile.ZipFile(out_path, "w") as dst_zip:
                for info in src_zip.infolist():
                    data = src_zip.read(info.filename)
                    if info.filename.endswith((".yaml", ".yml")) and "/databases/" in info.filename:
                        if uri:
                            text = data.decode("utf-8")
                            data = _patched_yaml(text, uri, force).encode("utf-8")
                    dst_zip.writestr(info, data)


def main() -> int:
    if len(sys.argv) != 3:
        print("Usage: patch_superset_imports.py <src_dir> <dst_dir>")
        return 1
    src_dir = Path(sys.argv[1])
    dst_dir = Path(sys.argv[2])
    if not src_dir.is_dir():
        print(f"Source dir not found: {src_dir}")
        return 1
    uri = os.getenv("SUPERSET_IMPORT_SQLALCHEMY_URI") or os.getenv("DWH_SQLALCHEMY_URI", "")
    force = os.getenv("SUPERSET_IMPORT_FORCE_URI", "0") == "1"
    patch_imports(src_dir, dst_dir, uri, force)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
