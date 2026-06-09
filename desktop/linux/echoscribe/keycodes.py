"""Linux input-event key code helpers."""

from __future__ import annotations

from dataclasses import dataclass


KEY_CODES: dict[str, int] = {
    "esc": 1,
    "1": 2,
    "2": 3,
    "3": 4,
    "4": 5,
    "5": 6,
    "6": 7,
    "7": 8,
    "8": 9,
    "9": 10,
    "0": 11,
    "minus": 12,
    "equal": 13,
    "backspace": 14,
    "tab": 15,
    "q": 16,
    "w": 17,
    "e": 18,
    "r": 19,
    "t": 20,
    "y": 21,
    "u": 22,
    "i": 23,
    "o": 24,
    "p": 25,
    "leftbrace": 26,
    "rightbrace": 27,
    "enter": 28,
    "leftctrl": 29,
    "ctrl": 29,
    "a": 30,
    "s": 31,
    "d": 32,
    "f": 33,
    "g": 34,
    "h": 35,
    "j": 36,
    "k": 37,
    "l": 38,
    "semicolon": 39,
    "apostrophe": 40,
    "grave": 41,
    "leftshift": 42,
    "shift": 42,
    "backslash": 43,
    "z": 44,
    "x": 45,
    "c": 46,
    "v": 47,
    "b": 48,
    "n": 49,
    "m": 50,
    "comma": 51,
    "dot": 52,
    "slash": 53,
    "rightshift": 54,
    "leftalt": 56,
    "alt": 56,
    "space": 57,
    "capslock": 58,
    "f1": 59,
    "f2": 60,
    "f3": 61,
    "f4": 62,
    "f5": 63,
    "f6": 64,
    "f7": 65,
    "f8": 66,
    "f9": 67,
    "f10": 68,
    "rightctrl": 97,
    "rightalt": 100,
    "home": 102,
    "up": 103,
    "pageup": 104,
    "left": 105,
    "right": 106,
    "end": 107,
    "down": 108,
    "pagedown": 109,
    "insert": 110,
    "delete": 111,
    "leftmeta": 125,
    "meta": 125,
    "super": 125,
    "rightmeta": 126,
    "compose": 127,
    "f11": 87,
    "f12": 88,
    "f13": 183,
    "f14": 184,
    "f15": 185,
    "f16": 186,
    "f17": 187,
    "f18": 188,
    "f19": 189,
    "f20": 190,
    "f21": 191,
    "f22": 192,
    "f23": 193,
    "f24": 194,
    "fn": 0x1D0,
    "fn_esc": 0x1D1,
    "fn_f1": 0x1D2,
    "fn_f2": 0x1D3,
    "fn_f3": 0x1D4,
    "fn_f4": 0x1D5,
    "fn_f5": 0x1D6,
    "fn_f6": 0x1D7,
    "fn_f7": 0x1D8,
    "fn_f8": 0x1D9,
    "fn_f9": 0x1DA,
    "fn_f10": 0x1DB,
    "fn_f11": 0x1DC,
    "fn_f12": 0x1DD,
    "fn_1": 0x1DE,
    "fn_2": 0x1DF,
    "fn_d": 0x1E0,
    "fn_e": 0x1E1,
    "fn_f": 0x1E2,
    "fn_s": 0x1E3,
    "fn_b": 0x1E4,
}


@dataclass(frozen=True)
class Hotkey:
    label: str
    codes: frozenset[int]


def normalize_key_name(name: str) -> str:
    key = name.strip().lower().replace("-", "_").replace(" ", "_")
    if key.startswith("key_"):
        key = key[4:]
    return key


def key_code(name: str) -> int:
    key = normalize_key_name(name)
    if key not in KEY_CODES:
        raise ValueError(f"Unknown key name: {name}")
    return KEY_CODES[key]


def parse_combo(combo: str) -> Hotkey:
    parts = [part.strip() for part in combo.split("+") if part.strip()]
    if not parts:
        raise ValueError("Hotkey combo is empty")
    return Hotkey(label=combo, codes=frozenset(key_code(part) for part in parts))


def parse_combo_list(value: str | list[str]) -> list[Hotkey]:
    combos = [value] if isinstance(value, str) else value
    return [parse_combo(combo) for combo in combos]
