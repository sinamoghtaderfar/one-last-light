#!/usr/bin/env python3
"""Package editable sources, excluding generated engine caches and exported builds."""

from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile
import hashlib


def main() -> None:
    project = Path(__file__).resolve().parents[1]
    destination = project.parent / "OneLastLight_Graybox_v0.2.zip"
    excluded = {".godot", ".git", "builds", "__pycache__"}
    sources = sorted(
        path
        for path in project.rglob("*")
        if path.is_file()
        and not excluded.intersection(path.relative_to(project).parts)
        and path.suffix != ".tmp"
    )
    with ZipFile(destination, "w", ZIP_DEFLATED, compresslevel=9) as archive:
        for path in sources:
            archive.write(path, Path("OneLastLight") / path.relative_to(project))
    with ZipFile(destination) as archive:
        failure = archive.testzip()
        if failure:
            raise RuntimeError(f"Archive integrity failure: {failure}")
        assert "OneLastLight/project.godot" in archive.namelist()
    checksum = hashlib.sha256(destination.read_bytes()).hexdigest()
    destination.with_suffix(".zip.sha256").write_text(
        f"{checksum}  {destination.name}\n", encoding="utf-8"
    )
    print(f"Packaged {len(sources)} files: {destination} ({destination.stat().st_size:,} bytes)")
    print(f"SHA-256: {checksum}")


if __name__ == "__main__":
    main()
