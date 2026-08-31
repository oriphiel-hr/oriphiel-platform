"""NKD 2007 labels for Sudreg activity codes (XX.XX.X → human title)."""

from __future__ import annotations

import json
import re
from functools import lru_cache
from pathlib import Path

_DATA = Path(__file__).resolve().parent / "data" / "nkd2007.json"

# Sudreg podrazred → closest NKD 2007 razred when codes diverge
_REMAP: dict[str, str] = {
    "41.00": "41.20",
    "56.11": "56.10",
    "56.22": "56.21",
    "62.10": "62.01",
    "62.20": "62.02",
    "62.90": "62.09",
    "63.10": "63.11",
    "64.21": "64.20",
    "68.11": "68.10",
    "68.12": "68.10",
    "70.20": "70.22",
    "72.10": "72.19",
    "74.14": "74.10",
    "74.99": "74.90",
    "80.01": "80.10",
    "81.23": "81.22",
    "82.10": "82.11",
    "25.53": "25.50",
    "31.00": "31.09",
    "43.24": "43.29",
    "43.35": "43.39",
    "43.41": "43.39",
    "46.83": "46.90",
    "47.12": "47.11",
    "49.33": "49.39",
    "95.31": "95.29",
    "96.10": "96.01",
    "96.21": "96.09",
    "96.22": "96.02",
    "96.23": "96.04",
    "96.99": "96.09",
    "35.14": "35.13",
}

_CODE_RE = re.compile(r"^(\d{2}(?:\.\d{1,2}){0,2})")
_HAS_LETTERS = re.compile(r"[A-Za-zÀ-žŠĐČĆŽšđčćž]")


@lru_cache(maxsize=1)
def _nkd() -> dict[str, str]:
    if not _DATA.is_file():
        return {}
    return json.loads(_DATA.read_text(encoding="utf-8"))


def _lookup_title(code: str) -> str | None:
    nkd = _nkd()
    if not code or not nkd:
        return None

    cands: list[str] = [code]
    if len(code) >= 5:
        base = code[:5]
        cands.append(base)
        if base in _REMAP:
            cands.append(_REMAP[base])
    if len(code) >= 4 and code[2] == ".":
        cands.append(code[:4])  # group XX.X
    if len(code) >= 2:
        cands.append(code[:2])  # division XX

    seen: set[str] = set()
    for cand in cands:
        if cand in seen:
            continue
        seen.add(cand)
        title = nkd.get(cand)
        if title:
            return title
    return None


def activity_title(raw: str | None) -> str | None:
    """Return NKD title for a Sudreg activity code/string, or None."""
    if not raw:
        return None
    text = str(raw).strip()
    if not text:
        return None

    # Already contains a human name (e.g. "80.01.2 Djelatnosti privatne…")
    if _HAS_LETTERS.search(text) and not re.fullmatch(r"[\d.\s]+", text):
        return None

    m = _CODE_RE.match(text)
    code = m.group(1) if m else text
    return _lookup_title(code)


def format_activity(raw: str | None, *, max_title: int = 90) -> str:
    """Display string: '62.20.0 — Savjetovanje u vezi s računalima'."""
    if not raw:
        return ""
    text = str(raw).strip()
    title = activity_title(text)
    if not title:
        return text
    if title.lower() in text.lower():
        return text
    if max_title and len(title) > max_title:
        title = title[: max_title - 1].rstrip() + "…"
    if re.fullmatch(r"[\d.]+", text):
        return f"{text} — {title}"
    return f"{text} — {title}"
