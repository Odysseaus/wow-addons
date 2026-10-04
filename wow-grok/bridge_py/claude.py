"""Anthropic Messages API client.

POST {claudeApiBase}/v1/messages  — default https://api.anthropic.com
Auth: x-api-key: <ANTHROPIC_API_KEY or cfg.claudeApiKey>  (never logged)
anthropic-version: 2023-06-01

Multi-turn uses local history. ``previous_response_id`` is accepted and
ignored (that field is xAI Responses-only). Plain chat: no tools, no web search.
"""
from __future__ import annotations

import json
import os
import re
import threading
import urllib.error
import urllib.request
from typing import Any, Callable

DEFAULT_MODEL = "claude-sonnet-4-5"
DEFAULT_BASE = "https://api.anthropic.com"
ANTHROPIC_VERSION = "2023-06-01"
DEFAULT_MAX_TOKENS = 8192

_SKIP_BLOCK_TYPES = {
    "thinking",
    "redacted_thinking",
    "tool_use",
    "tool_result",
    "server_tool_use",
    "web_search_tool_result",
}


def extract_text(data: Any) -> str:
    """Assistant text from an Anthropic message (content blocks)."""
    if not data or not isinstance(data, dict):
        return ""
    content = data.get("content")
    parts: list[str] = []
    if isinstance(content, str):
        if content:
            parts.append(content)
    elif isinstance(content, list):
        for block in content:
            if isinstance(block, str):
                if block:
                    parts.append(block)
                continue
            if not isinstance(block, dict):
                continue
            kind = block.get("type")
            if kind in _SKIP_BLOCK_TYPES:
                continue
            if kind not in (None, "text"):
                continue
            text = block.get("text")
            if isinstance(text, str) and text:
                parts.append(text)
    return "\n".join(parts).strip()


def _redact(text: str, api_key: str = "") -> str:
    if api_key and len(api_key) >= 8:
        text = text.replace(api_key, "[redacted]")
    text = re.sub(r"(?i)(x-api-key\s*[:=]\s*)\S+", r"\1[redacted]", text)
    text = re.sub(r"(?i)Bearer\s+\S+", "Bearer [redacted]", text)
    text = re.sub(r"sk-ant-[A-Za-z0-9_\-]+", "[redacted]", text)
    return text


def api_error_message(status: int, data: Any, raw: str, api_key: str = "") -> str:
    err = (data.get("error") if isinstance(data, dict) else None) or data
    msg = None
    if isinstance(err, dict):
        msg = err.get("message") or err.get("error")
    elif isinstance(err, str):
        msg = err
    if isinstance(msg, str) and msg.strip():
        return f"Claude API HTTP {status}: {_redact(msg.strip(), api_key)}"
    snippet = _redact(str(raw or ""), api_key)[:400]
    return f"Claude API HTTP {status}" + (f": {snippet}" if snippet else "")


def to_messages(history: list | None, inp: Any) -> list[dict]:
    """History ({role, content}) plus the current user input. No response ids."""
    msgs: list[dict] = []

    def add(role: str, content: Any) -> None:
        if content is None or content == "":
            return
        r = "assistant" if role in ("assistant", "grok") else "user"
        if not isinstance(content, str):
            content = str(content)
        msgs.append({"role": r, "content": content})

    for m in history or []:
        if not m or not isinstance(m, dict):
            continue
        content = m.get("content") if m.get("content") is not None else m.get("text")
        add(str(m.get("role") or "user"), content)
    if isinstance(inp, str):
        add("user", inp)
    elif isinstance(inp, list):
        for item in inp:
            if not item:
                continue
            if isinstance(item, str):
                add("user", item)
            elif isinstance(item, dict):
                content = item.get("content") if item.get("content") is not None else item.get("text")
                if content is None:
                    content = ""
                add(str(item.get("role") or "user"), content)
    elif isinstance(inp, dict):
        content = inp.get("content") if inp.get("content") is not None else inp.get("text")
        add(str(inp.get("role") or "user"), content if content is not None else str(inp))
    elif inp is not None:
        add("user", str(inp))
    return msgs


class ClaudeError(Exception):
    def __init__(self, message: str, status: int | None = None):
        super().__init__(message)
        self.status = status
        self.message = message


def post_message(
    *,
    api_key: str,
    model: str | None = None,
    api_base: str | None = None,
    messages: list | None = None,
    system: str | None = None,
    max_tokens: int | None = None,
    timeout: float = 600.0,
) -> dict:
    base = str(api_base or DEFAULT_BASE).rstrip("/")
    url = base + "/v1/messages"
    msgs = list(messages or [])
    if not msgs:
        raise ClaudeError("Claude API call has no messages")
    body: dict[str, Any] = {
        "model": model or DEFAULT_MODEL,
        "max_tokens": int(max_tokens or DEFAULT_MAX_TOKENS),
        "messages": msgs,
    }
    if system:
        body["system"] = system

    data = json.dumps(body).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=data,
        method="POST",
        headers={
            "Content-Type": "application/json",
            "x-api-key": api_key,
            "anthropic-version": ANTHROPIC_VERSION,
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            raw = resp.read().decode("utf-8", errors="replace")
            status = resp.status
    except urllib.error.HTTPError as e:
        raw = e.read().decode("utf-8", errors="replace")
        status = e.code
        parsed = None
        try:
            parsed = json.loads(raw)
        except json.JSONDecodeError:
            pass
        err = ClaudeError(
            api_error_message(status, parsed, raw, api_key),
            status=status,
        )
        raise err from None
    except urllib.error.URLError as e:
        raise ClaudeError(f"Claude API network error: {e.reason}") from e

    try:
        parsed = json.loads(raw)
    except json.JSONDecodeError:
        raise ClaudeError("Claude API returned non-JSON") from None
    if not isinstance(parsed, dict):
        raise ClaudeError("Claude API returned non-JSON")
    if parsed.get("type") == "error":
        raise ClaudeError(
            api_error_message(status, parsed, raw, api_key),
            status=status,
        )
    text = extract_text(parsed)
    rid = parsed.get("id") or ""
    if not rid and not text:
        raise ClaudeError("Claude API returned an empty response")
    return {"id": rid, "text": text or ""}


def chat(
    *,
    api_key: str | None = None,
    model: str | None = None,
    api_base: str | None = None,
    input: Any = None,
    previous_response_id: str | None = None,
    system: str | None = None,
    history: list | None = None,
    on_progress: Callable[[], None] | None = None,
    timeout: float = 600.0,
    max_tokens: int | None = None,
) -> dict:
    """Same return shape as ``xai.chat``: ``{"id", "text"}``.

    ``previous_response_id`` is ignored. Turns are the history list plus ``input``.
    """
    # xAI-only. Accepted so bridge can share one call shape.
    del previous_response_id
    key = api_key or os.environ.get("ANTHROPIC_API_KEY") or ""
    if not key:
        raise ClaudeError(
            "Missing Anthropic API key. Set the ANTHROPIC_API_KEY environment variable "
            'or "claudeApiKey" in config.json.'
        )
    model = model or DEFAULT_MODEL
    stop = threading.Event()
    beat: threading.Timer | None = None

    def _pulse() -> None:
        if stop.is_set():
            return
        if on_progress:
            try:
                on_progress()
            except Exception:
                pass
        nonlocal beat
        beat = threading.Timer(20.0, _pulse)
        beat.daemon = True
        beat.start()

    if on_progress:
        try:
            on_progress()
        except Exception:
            pass
        beat = threading.Timer(20.0, _pulse)
        beat.daemon = True
        beat.start()

    try:
        messages = to_messages(history, input)
        return post_message(
            api_key=key,
            model=model,
            api_base=api_base,
            messages=messages,
            system=system,
            max_tokens=max_tokens,
            timeout=timeout,
        )
    finally:
        stop.set()
        if beat:
            beat.cancel()
