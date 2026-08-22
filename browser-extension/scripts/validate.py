#!/usr/bin/env python3
"""Fail-closed validation for exact EchoScribe release and source archives."""
from __future__ import annotations

import hashlib
import json
import re
import tempfile
from pathlib import Path
from zipfile import ZipFile

ROOT = Path(__file__).resolve().parent.parent
TARGETS = ("chrome",)
ICON_SOURCE = ROOT / "assets" / "icons"
FORBIDDEN_ENTRIES = (
    ".git", ".hermes", "AGENTS.md", "node_modules", "tests/", "coverage/",
    ".env", "_dev_tools", ".map", "package-lock.json",
)
PRIVATE_PATH = re.compile(re.escape(str(Path.home())) + r"|[A-Z]:\\Users\\[A-Za-z0-9._-]+", re.I)
FORBIDDEN_TEXT = {
    "native messaging": re.compile(r"nativeMessaging|sendNativeMessage|connectNative"),
    "local endpoint": re.compile(r"localhost|127\.0\.0\.1|0\.0\.0\.0"),
    "private home path": PRIVATE_PATH,
    "broad host permission": re.compile(r"<all_urls>|https?://\*/\*"),
    "remote executable code": re.compile(r"<(?:script|iframe)[^>]+(?:src|href)=[\"']https?://", re.I),
}
SOURCE_FORBIDDEN_TEXT = {
    "private home path": PRIVATE_PATH,
}
ALLOWED_HOSTS = {
    "https://api.openai.com/*",
    "https://api.anthropic.com/*",
    "https://generativelanguage.googleapis.com/*",
    "https://api.x.ai/*",
}
PACKAGE_VERSION = json.loads((ROOT / "package.json").read_text(encoding="utf-8"))["version"]
CHROMIUM_EXTENSION_KEY = "MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAw5feX+pKmvnJP7DUnuhR+Hr3C+NoZu8PK7XLBwGL7MOatsOMPJUB7GLLMA6x/m5PXbpHnQ78IjvXzsXW3AqYQevxWKFvSB5oBS1uaIWZkNH5AG+z/beIInFtZHWDfWkIsBYhpUu/RdGlrB5cuyWUCzxlMH+7EWu3yGHUo5qoNOwjNUx8ih8OS4iQuvq78RX8JuOjKh8xUiDxDd761CZYJJEn7cpq9onOWymYUfwFkrxE3L2SrWj7p0DZyP+L2iVFe0W9txChZgjto5mlMcdn9mrwaPDmZvbxRRCa0kIB5Qsjr4oVeYSVEOFMZoWLF8iDzBU+3JOAvCNaHeualJygiQIDAQAB"


def fail(message: str) -> None:
    raise SystemExit(f"VALIDATION FAILED: {message}")


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def inspect_manifest(target: str, manifest: dict) -> None:
    if manifest.get("manifest_version") != 3 or manifest.get("name") != "EchoScribe Web Summary":
        fail(f"{target}: invalid identity or manifest version")
    if manifest.get("version") != PACKAGE_VERSION:
        fail(f"{target}: manifest/package version mismatch")
    if "nativeMessaging" in manifest.get("permissions", []):
        fail(f"{target}: native messaging present")
    if set(manifest.get("host_permissions", [])) != ALLOWED_HOSTS:
        fail(f"{target}: provider host allowlist differs")
    if any(value in manifest.get("permissions", []) for value in ("tabs", "webRequest", "history")):
        fail(f"{target}: excessive permission")
    csp = manifest.get("content_security_policy", {}).get("extension_pages", "")
    if "'unsafe-eval'" in csp or "'unsafe-inline'" in csp or "script-src 'self'" not in csp:
        fail(f"{target}: unsafe CSP")
    if target == "firefox":
        gecko = manifest.get("browser_specific_settings", {}).get("gecko", {})
        if manifest.get("background") != {"scripts": ["background.js"]}:
            fail("firefox: background.scripts missing")
        if "key" in manifest:
            fail("firefox: Chromium key present")
        if gecko.get("id") != "echoscribe@wean.de" or int(gecko.get("strict_min_version", "0").split(".")[0]) < 142:
            fail("firefox: Gecko identity/minimum version invalid")
        required = gecko.get("data_collection_permissions", {}).get("required", [])
        if set(required) != {"authenticationInfo", "websiteContent"}:
            fail("firefox: data permission disclosure mismatch")
    else:
        if "key" in manifest:
            fail(f"{target}: store ZIP must omit key; Chrome/Edge listings assign identity")
        if manifest.get("background") != {"service_worker": "background.js"}:
            fail(f"{target}: Chromium service worker missing")


def scan_text(scope: str, name: str, data: bytes, patterns: dict[str, re.Pattern]) -> None:
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError:
        return
    for label, pattern in patterns.items():
        if pattern.search(text):
            fail(f"{scope}: {label} found in {name}")


def inspect_archive(target: str, archive_path: Path) -> None:
    dist = ROOT / "dist" / target
    with ZipFile(archive_path) as archive:
        names = archive.namelist()
        if "manifest.json" not in names or any(name.startswith("/") for name in names):
            fail(f"{target}: manifest is not at archive root")
        for name in names:
            if any(part.lower() in name.lower() for part in FORBIDDEN_ENTRIES):
                fail(f"{target}: forbidden archive entry {name}")
        inspect_manifest(target, json.loads(archive.read("manifest.json")))
        for name in names:
            data = archive.read(name)
            source = dist / name
            if not source.is_file():
                fail(f"{target}: archive differs from dist at {name}")
            expected = source.read_bytes()
            if name == "manifest.json" and target == "chrome":
                dist_manifest = json.loads(expected.decode("utf-8"))
                if dist_manifest.get("key") != CHROMIUM_EXTENSION_KEY:
                    fail(f"{target}: unpacked dist must keep the Chromium public key")
                dist_manifest.pop("key", None)
                expected = (json.dumps(dist_manifest, indent=2) + "\n").encode("utf-8")
            if data != expected:
                fail(f"{target}: archive differs from dist at {name}")
            scan_text(target, name, data, FORBIDDEN_TEXT)
            try:
                text = data.decode("utf-8")
            except UnicodeDecodeError:
                continue
            if name.endswith(".html") and re.search(r"<script(?![^>]*\bsrc=)|\son\w+=", text, re.I):
                fail(f"{target}: inline executable HTML in {name}")
        expected = sorted(path.relative_to(dist).as_posix() for path in dist.rglob("*") if path.is_file())
        if sorted(names) != expected or len(names) != len(set(names)):
            fail(f"{target}: ZIP inventory differs from dist or contains duplicates")
        with tempfile.TemporaryDirectory() as temporary:
            archive.extractall(temporary)
            if not (Path(temporary) / "manifest.json").is_file():
                fail(f"{target}: extraction verification failed")


def source_inventory() -> list[Path]:
    files = [
        ROOT / ".gitignore", ROOT / "LICENSE", ROOT / "README.md", ROOT / "TRADEMARKS.md",
        ROOT / "eslint.config.js", ROOT / "package.json", ROOT / "package-lock.json",
    ]
    for directory in ("src", "scripts", "tests", "store", "assets/icons"):
        files.extend(path for path in (ROOT / directory).rglob("*") if path.is_file())
    files.extend(path for path in (ROOT / "assets").iterdir() if path.is_file())
    if not ICON_SOURCE.is_dir():
        fail("source: EchoScribe icons missing")
    return sorted(set(files))


def inspect_source_archive(archive_path: Path) -> None:
    expected_files = source_inventory()
    expected = {path.relative_to(ROOT).as_posix(): path for path in expected_files}
    with ZipFile(archive_path) as archive:
        names = archive.namelist()
        if sorted(names) != sorted(expected) or len(names) != len(set(names)):
            fail("source: inventory mismatch or duplicate entry")
        for name, source in expected.items():
            data = archive.read(name)
            if data != source.read_bytes():
                fail(f"source: archive differs from workspace at {name}")
            scan_text("source", name, data, SOURCE_FORBIDDEN_TEXT)


def main() -> None:
    sums = json.loads((ROOT / "artifacts" / "SHA256SUMS.json").read_text(encoding="utf-8"))
    for target in TARGETS:
        matches = list((ROOT / "artifacts").glob(f"echoscribe-web-summary-{target}-v*.zip"))
        if len(matches) != 1:
            fail(f"{target}: expected exactly one artifact")
        archive = matches[0]
        if archive.name != f"echoscribe-web-summary-{target}-v{PACKAGE_VERSION}.zip":
            fail(f"{target}: archive/package version mismatch")
        if sums.get(archive.name) != digest(archive):
            fail(f"{target}: SHA-256 mismatch")
        inspect_archive(target, archive)
        print(f"{target}: PASS {archive.name} {digest(archive)}")
    source_matches = list((ROOT / "artifacts").glob("echoscribe-web-summary-source-v*.zip"))
    if len(source_matches) != 1:
        fail("source: expected exactly one artifact")
    source_archive = source_matches[0]
    if source_archive.name != f"echoscribe-web-summary-source-v{PACKAGE_VERSION}.zip":
        fail("source: archive/package version mismatch")
    if sums.get(source_archive.name) != digest(source_archive):
        fail("source: SHA-256 mismatch")
    inspect_source_archive(source_archive)
    print(f"source: PASS {source_archive.name} {digest(source_archive)}")
    print("release_validation=PASS")


if __name__ == "__main__":
    main()
