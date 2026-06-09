"""Module entry point for EchoScribe Linux integration tooling."""

from __future__ import annotations

import argparse
import logging
import os
import sys
from pathlib import Path


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="echoscribe")
    parser.add_argument(
        "command",
        nargs="?",
        choices=[
            "run",
            "doctor",
            "config-path",
            "config-tui",
            "config-get",
            "config-set",
            "gnome-worker",
            "sideband",
            "native-host",
        ],
        default="run",
    )
    parser.add_argument("worker_args", nargs=argparse.REMAINDER)
    parser.add_argument("--debug", action="store_true")
    args = parser.parse_args(argv)
    logging.basicConfig(
        level=logging.DEBUG if args.debug else logging.INFO,
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
    )
    project_dir = Path(__file__).resolve().parents[1]
    if args.command == "gnome-worker":
        from .gnome_worker import main as worker_main

        return worker_main(args.worker_args)
    if args.command == "sideband":
        from .sideband import main as sideband_main

        return sideband_main(args.worker_args)
    if args.command == "native-host":
        from .native_host import main as native_host_main

        return native_host_main(args.worker_args)

    from .config import load_config

    config = load_config(project_dir)
    if args.command == "config-path":
        print(config.path or "~/.config/echoscribe/config.toml")
        return 0
    if args.command == "config-tui":
        from .config_tui import run_config_tui

        return run_config_tui(config)
    if args.command == "config-get":
        if args.worker_args == ["transcription-provider"]:
            print(config.active_provider("transcription"))
            return 0
        if args.worker_args == ["summary-provider"]:
            print(config.active_provider("summary"))
            return 0
        if len(args.worker_args) == 2 and args.worker_args[0] == "api-key-status":
            from .config import normalize_provider

            provider = normalize_provider(args.worker_args[1])
            print("set" if config.provider_api_key(provider) else "missing")
            return 0
        if len(args.worker_args) == 2 and args.worker_args[0] == "api-key":
            from .config import normalize_provider

            provider = normalize_provider(args.worker_args[1])
            print(config.provider_api_key(provider) or "")
            return 0
        if len(args.worker_args) == 2 and args.worker_args[0] == "summary-model":
            from .config import SUMMARY_PROVIDERS, normalize_provider

            provider = normalize_provider(args.worker_args[1])
            if provider not in SUMMARY_PROVIDERS:
                print(f"echoscribe: {provider} does not support web summaries", file=sys.stderr)
                return 2
            print(config.summary_model(provider))
            return 0
        print(
            "echoscribe: supported config-get keys: transcription-provider, summary-provider, "
            "api-key-status <provider>, api-key <provider>, summary-model <provider>",
            file=sys.stderr,
        )
        return 2
    if args.command == "config-set":
        if len(args.worker_args) == 2 and args.worker_args[0] == "transcription-provider":
            from .config import normalize_provider
            from .config_tui import ensure_config_file, set_value

            provider = normalize_provider(args.worker_args[1])
            path = config.path or Path("~/.config/echoscribe/config.toml").expanduser()
            ensure_config_file(path)
            set_value(path, "providers", "transcription", provider)
            print(provider)
            return 0
        if len(args.worker_args) == 2 and args.worker_args[0] == "summary-provider":
            from .config import SUMMARY_PROVIDERS, normalize_provider
            from .config_tui import ensure_config_file, set_value

            provider = normalize_provider(args.worker_args[1])
            if provider not in SUMMARY_PROVIDERS:
                print(f"echoscribe: {provider} does not support web summaries", file=sys.stderr)
                return 2
            path = config.path or Path("~/.config/echoscribe/config.toml").expanduser()
            ensure_config_file(path)
            set_value(path, "providers", "summary", provider)
            print(provider)
            return 0
        if len(args.worker_args) == 2 and args.worker_args[0] == "api-key":
            from .config import default_api_key_env, normalize_provider, write_env_value

            provider = normalize_provider(args.worker_args[1])
            value = sys.stdin.read().strip()
            if not value:
                print("echoscribe: refusing to store empty API key", file=sys.stderr)
                return 2
            write_env_value(config.env_file, default_api_key_env(provider), value)
            print(f"{provider}: set")
            return 0
        if len(args.worker_args) == 3 and args.worker_args[0] == "summary-model":
            from .config import SUMMARY_PROVIDERS, normalize_provider
            from .config_tui import ensure_config_file, set_value

            provider = normalize_provider(args.worker_args[1])
            if provider not in SUMMARY_PROVIDERS:
                print(f"echoscribe: {provider} does not support web summaries", file=sys.stderr)
                return 2
            model = args.worker_args[2].strip()
            if not model:
                print("echoscribe: refusing to store empty summary model", file=sys.stderr)
                return 2
            path = config.path or Path("~/.config/echoscribe/config.toml").expanduser()
            ensure_config_file(path)
            set_value(path, provider, "summary_model", model)
            print(model)
            return 0
        print(
            "echoscribe: usage: echoscribe config-set transcription-provider <provider> | "
            "echoscribe config-set summary-provider <provider> | "
            "echoscribe config-set summary-model <provider> <model> | "
            "echoscribe config-set api-key <provider>",
            file=sys.stderr,
        )
        return 2
    if args.command == "doctor":
        from .app import doctor

        for line in doctor(config):
            print(line)
        return 0
    if args.command == "run" and sys.platform.startswith("linux") and not os.environ.get("ECHOSCRIBE_ALLOW_LEGACY_LINUX_RUN"):
        print(
            "echoscribe: Linux dictation is provided by the GNOME Shell extension. "
            "Run ./scripts/install_gnome_extension.sh and use python -m echoscribe gnome-worker for worker commands. "
            "Set ECHOSCRIBE_ALLOW_LEGACY_LINUX_RUN=1 only for legacy backend debugging.",
            file=sys.stderr,
        )
        return 2
    try:
        if sys.platform.startswith("linux"):
            # Prefer XWayland when available so the legacy floating popup can be placed reliably.
            os.environ.setdefault("GDK_BACKEND", "x11,wayland")
        from .app import EchoScribeApp

        EchoScribeApp(config).run()
        return 0
    except KeyboardInterrupt:
        return 130
    except Exception as exc:
        print(f"echoscribe: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
