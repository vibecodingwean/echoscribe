"""Module entry point for EchoScribe Linux integration tooling."""

from __future__ import annotations

import argparse
import logging
import sys
from pathlib import Path


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="echoscribe")
    parser.add_argument(
        "command",
        nargs="?",
        choices=[
            "doctor",
            "config-tui",
            "config-get",
            "config-set",
            "gnome-worker",
            "native-host",
        ],
        default="doctor",
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
    if args.command == "native-host":
        from .native_host import main as native_host_main

        return native_host_main(args.worker_args)

    from .config import load_config

    config = load_config(project_dir)
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
        if len(args.worker_args) == 2 and args.worker_args[0] == "summary-model":
            from .config import SUMMARY_PROVIDERS, normalize_provider

            provider = normalize_provider(args.worker_args[1])
            if provider not in SUMMARY_PROVIDERS:
                print(f"echoscribe: {provider} does not support web summaries", file=sys.stderr)
                return 2
            print(config.summary_model(provider))
            return 0
        if len(args.worker_args) == 2 and args.worker_args[0] == "transcription-model":
            from .config import TRANSCRIPTION_PROVIDERS, normalize_provider

            provider = normalize_provider(args.worker_args[1])
            if provider not in TRANSCRIPTION_PROVIDERS:
                print(f"echoscribe: {provider} does not support speech-to-text", file=sys.stderr)
                return 2
            section = config.data.get(provider, {})
            model = str(section.get("transcription_model", "") if isinstance(section, dict) else "").strip()
            print(model)
            return 0
        if args.worker_args == ["local-ai-llm-url"]:
            section = config.data.get("localai", {})
            print(str(section.get("llm_url", "") if isinstance(section, dict) else "").strip())
            return 0
        if args.worker_args == ["local-ai-whisper-url"]:
            section = config.data.get("localai", {})
            print(str(section.get("whisper_url", "") if isinstance(section, dict) else "").strip())
            return 0
        print(
            "echoscribe: supported config-get keys: transcription-provider, summary-provider, "
            "api-key-status <provider>, summary-model <provider>, "
            "transcription-model <provider>, local-ai-llm-url, local-ai-whisper-url",
            file=sys.stderr,
        )
        return 2
    if args.command == "config-set":
        if len(args.worker_args) == 2 and args.worker_args[0] == "transcription-provider":
            from .config import TRANSCRIPTION_PROVIDERS, normalize_provider
            from .config_tui import ensure_config_file, set_value

            provider = normalize_provider(args.worker_args[1])
            if provider not in TRANSCRIPTION_PROVIDERS:
                print(f"echoscribe: {provider} does not support speech-to-text", file=sys.stderr)
                return 2
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
            if provider == "localai":
                print("echoscribe: localai does not use an API key", file=sys.stderr)
                return 2
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
        if len(args.worker_args) == 3 and args.worker_args[0] == "transcription-model":
            from .config import TRANSCRIPTION_PROVIDERS, normalize_provider
            from .config_tui import ensure_config_file, set_value

            provider = normalize_provider(args.worker_args[1])
            if provider not in TRANSCRIPTION_PROVIDERS:
                print(f"echoscribe: {provider} does not support speech-to-text", file=sys.stderr)
                return 2
            model = args.worker_args[2].strip()
            if not model:
                print("echoscribe: refusing to store empty transcription model", file=sys.stderr)
                return 2
            path = config.path or Path("~/.config/echoscribe/config.toml").expanduser()
            ensure_config_file(path)
            set_value(path, provider, "transcription_model", model)
            print(model)
            return 0
        if len(args.worker_args) == 2 and args.worker_args[0] == "local-ai-llm-url":
            from .config_tui import ensure_config_file, set_value

            value = args.worker_args[1].strip()
            if not value:
                print("echoscribe: refusing to store empty Local AI LLM URL", file=sys.stderr)
                return 2
            path = config.path or Path("~/.config/echoscribe/config.toml").expanduser()
            ensure_config_file(path)
            set_value(path, "localai", "llm_url", value)
            print(value)
            return 0
        if len(args.worker_args) == 2 and args.worker_args[0] == "local-ai-whisper-url":
            from .config_tui import ensure_config_file, set_value

            value = args.worker_args[1].strip()
            if not value:
                print("echoscribe: refusing to store empty Local AI Whisper URL", file=sys.stderr)
                return 2
            path = config.path or Path("~/.config/echoscribe/config.toml").expanduser()
            ensure_config_file(path)
            set_value(path, "localai", "whisper_url", value)
            print(value)
            return 0
        print(
            "echoscribe: usage: echoscribe config-set transcription-provider <provider> | "
            "echoscribe config-set summary-provider <provider> | "
            "echoscribe config-set summary-model <provider> <model> | "
            "echoscribe config-set transcription-model <provider> <model> | "
            "echoscribe config-set local-ai-llm-url <url> | "
            "echoscribe config-set local-ai-whisper-url <url> | "
            "echoscribe config-set api-key <provider>",
            file=sys.stderr,
        )
        return 2
    if args.command == "doctor":
        from .linux import doctor

        for line in doctor(config):
            print(line)
        return 0
    print("echoscribe: unsupported command", file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
