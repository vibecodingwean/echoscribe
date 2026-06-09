"""Helpers used by setup scripts to render user configuration."""

from __future__ import annotations

import re


def render_config_template(
    template: str,
    *,
    dictation_hold: str,
    transcription_provider: str,
    paste_shortcut: str | None = None,
) -> str:
    text = template
    text = re.sub(r'dictation_hold = \[[^\]]+\]', f'dictation_hold = ["{dictation_hold}"]', text)
    text = re.sub(r'(?m)^transcription = "[^"]+"', f'transcription = "{transcription_provider}"', text)
    if paste_shortcut is not None:
        text = re.sub(r'(?m)^shortcut = "[^"]+"', f'shortcut = "{paste_shortcut}"', text)
    return text
