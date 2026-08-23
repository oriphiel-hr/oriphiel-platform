#!/usr/bin/env python3
"""Ollama enrichment za poruku: ai_summary, ai_priority, ai_draft."""

from __future__ import annotations

import json
import os
import re
import urllib.error
import urllib.request
from typing import Any, Optional


def env(name: str, default: str = "") -> str:
    return os.environ.get(name, default).strip()


def truthy(name: str, default: str = "0") -> bool:
    return env(name, default) in ("1", "true", "TRUE", "yes", "YES")


def _clip(text: str, max_len: int) -> str:
    text = (text or "").strip()
    if len(text) <= max_len:
        return text
    return text[: max_len - 3].rstrip() + "..."


def build_prompt(from_addr: str, subject: str, body_text: str) -> str:
    body = _clip(body_text.replace("\r\n", "\n"), 6000)
    subj = _clip(subject, 500)
    sender = _clip(from_addr, 200)
    return f"""Analiziraj dolazni email na hrvatskom. Vrati SAMO JSON objekt (bez markdowna) s kljucevima:
- summary: 1-3 recenice sazetka
- priority: jedna od low, normal, high, urgent
- draft_reply: kratki nacrt odgovora (2-4 recenice, profesionalan ton)

Od: {sender}
Predmet: {subj}

Tijelo:
{body}
"""


def parse_ai_json(raw: str) -> dict[str, str]:
    raw = (raw or "").strip()
    if not raw:
        raise ValueError("prazan Ollama odgovor")
    m = re.search(r"\{[\s\S]*\}", raw)
    if not m:
        raise ValueError(f"nema JSON u odgovoru: {raw[:200]}")
    data = json.loads(m.group(0))
    summary = (
        data.get("summary")
        or data.get("ai_summary")
        or data.get("sazetak")
        or data.get("sažetak")
        or data.get("title")
        or data.get("text")
        or ""
    )
    draft = (
        data.get("draft_reply")
        or data.get("ai_draft")
        or data.get("draft")
        or data.get("odgovor")
        or ""
    )
    priority = str(
        data.get("priority") or data.get("ai_priority") or "normal"
    ).lower().strip()
    if priority not in ("low", "normal", "high", "urgent"):
        priority = "normal"
    summary_s = str(summary).strip()
    draft_s = str(draft).strip()
    if not summary_s:
        summary_s = "(nema sažetka)"
    return {
        "ai_summary": _clip(summary_s, 4000),
        "ai_priority": priority,
        "ai_draft": _clip(draft_s, 8000),
    }


def enrich_message(
    from_addr: str,
    subject: str,
    body_text: str,
    *,
    ollama_url: Optional[str] = None,
    model: Optional[str] = None,
    timeout_sec: int = 180,
) -> dict[str, str]:
    url_base = (ollama_url or env("OLLAMA_URL", "http://127.0.0.1:11434")).rstrip("/")
    model = model or env("OLLAMA_MODEL", "llama3.1:8b")
    prompt = build_prompt(from_addr, subject, body_text)

    payload = {
        "model": model,
        "prompt": prompt,
        "stream": False,
        "format": "json",
        "options": {"temperature": 0.2},
    }
    req = urllib.request.Request(
        f"{url_base}/api/generate",
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout_sec) as resp:
            body = json.loads(resp.read().decode("utf-8", errors="replace"))
    except urllib.error.URLError as exc:
        raise RuntimeError(f"Ollama nedostupan ({url_base}): {exc}") from exc

    text = body.get("response") or ""
    return parse_ai_json(text)


def enrich_if_enabled(from_addr: str, subject: str, body_text: str) -> Optional[dict[str, str]]:
    if not truthy("RUN_AI", "0"):
        return None
    if not (body_text or subject):
        return None
    try:
        return enrich_message(from_addr, subject, body_text)
    except Exception as exc:
        print(f"AI skip: {exc}", flush=True)
        return None
