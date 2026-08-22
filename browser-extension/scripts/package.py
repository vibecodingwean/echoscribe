#!/usr/bin/env python3
"""Create deterministic EchoScribe store ZIP files from explicit dist directories."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile, ZipInfo

ROOT = Path(__file__).resolve().parent.parent
DIST = ROOT / "dist"
ARTIFACTS = ROOT / "artifacts"
TARGETS = ("chrome",)
FIXED_TIME = (2020, 1, 1, 0, 0, 0)


def store_manifest_bytes(source: Path, target: str) -> bytes:
    data = source.read_bytes()
    if source.name != "manifest.json" or target != "chrome":
        return data
    manifest = json.loads(data.decode("utf-8"))
    manifest.pop("key", None)
    return (json.dumps(manifest, indent=2) + "\n").encode("utf-8")


def add_file(archive: ZipFile, source: Path, name: str, target: str = "") -> None:
    info = ZipInfo(name, FIXED_TIME)
    info.compress_type = ZIP_DEFLATED
    info.external_attr = (0o100644 & 0xFFFF) << 16
    archive.writestr(info, store_manifest_bytes(source, target))


def main() -> None:
    ARTIFACTS.mkdir(parents=True, exist_ok=True)
    for old in ARTIFACTS.glob("*.zip"):
        old.unlink()
    hashes = {}
    for target in TARGETS:
        source = DIST / target
        manifest = json.loads((source / "manifest.json").read_text(encoding="utf-8"))
        output = ARTIFACTS / f"echoscribe-web-summary-{target}-v{manifest['version']}.zip"
        files = sorted(path for path in source.rglob("*") if path.is_file())
        if not files:
            raise SystemExit(f"No files found for {target}")
        with ZipFile(output, "w") as archive:
            for path in files:
                add_file(archive, path, path.relative_to(source).as_posix(), target)
        digest = hashlib.sha256(output.read_bytes()).hexdigest()
        hashes[output.name] = digest
        print(f"{output.name}  {digest}")

    version = json.loads((ROOT / "package.json").read_text(encoding="utf-8"))["version"]
    source_output = ARTIFACTS / f"echoscribe-web-summary-source-v{version}.zip"
    source_files = [
        ROOT / ".gitignore", ROOT / "LICENSE", ROOT / "README.md", ROOT / "TRADEMARKS.md",
        ROOT / "eslint.config.js", ROOT / "package.json", ROOT / "package-lock.json",
    ]
    for directory in ("src", "scripts", "tests", "store", "assets/icons"):
        source_files.extend(path for path in (ROOT / directory).rglob("*") if path.is_file())
    source_files.extend(path for path in (ROOT / "assets").iterdir() if path.is_file())
    if not (ROOT / "assets" / "icons").is_dir():
        raise SystemExit("EchoScribe icons are missing")
    source_files = sorted(set(source_files))
    with ZipFile(source_output, "w") as archive:
        for path in source_files:
            add_file(archive, path, path.relative_to(ROOT).as_posix())
    source_digest = hashlib.sha256(source_output.read_bytes()).hexdigest()
    hashes[source_output.name] = source_digest
    print(f"{source_output.name}  {source_digest}")

    ordered_hashes = dict(sorted(hashes.items()))
    (ARTIFACTS / "SHA256SUMS.json").write_text(json.dumps(ordered_hashes, indent=2) + "\n", encoding="utf-8")
    checksum_text = "".join(f"{digest}  {name}\n" for name, digest in ordered_hashes.items())
    (ARTIFACTS / "SHA256SUMS").write_text(checksum_text, encoding="utf-8")


if __name__ == "__main__":
    main()
