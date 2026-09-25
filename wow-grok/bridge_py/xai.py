"""xAI Grok API client (Responses). Ported from bridge/xai.js.

POST {apiBase}/responses  — default https://api.x.ai/v1
Auth: Authorization: Bearer <XAI_API_KEY or cfg.apiKey>  (never logged)

Multi-turn: previous_response_id; on rejection, retry with local history.
"""
from __future__ import annotations

import json
import os
import re
import threading
import urllib.error
import urllib.request
from typing import Any, Callable

DEFAULT_MODEL = "grok-4-latest"
DEFAULT_BASE = "https://api.x.ai/v1"


def extract_text(data: Any) -> str:
    if not data or not isinstance(data, dict):
        return ""
    ot = data.get("output_text")
    if isinstance(ot, str) and ot.strip():
        return ot
    parts: list[str] = []

    def take(c: Any) -> None:
        if not c:
            return
        if isinstance(c, str):
            if c:
                parts.append(c)
            return
        if isinstance(c, dict):
            if isinstance(c.get("text"), str):
                parts.append(c["text"])
            elif isinstance(c.get("output_text"), str):
                parts.append(c["output_text"])

    for item in data.get("output") or []:
        if not item:
            continue
        if isinstance(item, str):
            parts.append(item)
            continue
        if not isinstance(item, dict):
            continue
        t = item.get("type")
        if t in ("output_text", "text"):
            take(item)
            continue
        is_msg = t == "message" or item.get("role") == "assistant"
        if not is_msg and t and t != "message":
            continue
        content = item.get("content")
        if isinstance(content, str):
            take(content)
        elif isinstance(content, list):
            for c in content:
                take(c)
        else:
            take(item)
    return "\n".join(parts).strip()


def api_error_message(status: int, data: Any, raw: str) -> str:
    err = (data.get("error") if isinstance(data, dict) else None) or data
    msg = None
    if isinstance(err, dict):
        msg = err.get("message") or err.get("error")
    elif isinstance(err, str):
        msg = err
    if isinstance(msg, str) and msg.strip():
        return f"xAI API HTTP {status}: {msg.strip()}"
    snippet = re.sub(r"Bearer\s+\S+", "Bearer [redacted]", str(raw or ""), flags=re.I)[
        :400
    ]
    return f"xAI API HTTP {status}" + (f": {snippet}" if snippet else "")


def is_previous_response_error(err: BaseException) -> bool:
    status = getattr(err, "status", None)
    if status in (400, 404):
        return True
    m = str(getattr(err, "message", None) or err or "").lower()
    return bool(
        re.search(
            r"previous[_ ]response|not found|unknown response|expired|invalid.*response",
            m,
        )
    )


def as_user_input(inp: Any) -> Any:
    if isinstance(inp, str):
        return inp
    if isinstance(inp, list):
        return inp
    if isinstance(inp, dict) and (inp.get("content") or inp.get("role")):
        return [inp]
    return str(inp if inp is not None else "")


def to_input_messages(history: list | None, inp: Any) -> list[dict]:
    msgs: list[dict] = []
    for m in history or []:
        if not m:
            continue
        role = (
            "assistant"
            if m.get("role") in ("assistant", "grok")
            else "user"
        )
        content = m.get("content") if m.get("content") is not None else m.get("text")
        if content is None or content == "":
            continue
        msgs.append({"role": role, "content": str(content)})
    if isinstance(inp, str):
        if inp:
            msgs.append({"role": "user", "content": inp})
    elif isinstance(inp, list):
        for item in inp:
            if not item:
                continue
            if isinstance(item, str):
                msgs.append({"role": "user", "content": item})
            else:
                msgs.append(item)
    elif isinstance(inp, dict):
        msgs.append(inp)
    return msgs


def with_game_context_prefix(user_input: Any, system: str | None) -> Any:
    """Fallback: prepend a short [Game context] block when resuming without instructions.

    Prefer sending `instructions` every turn (see post_response). Use this only when
    the API rejects instructions + previous_response_id together.
    """
    ctx = (system or "").strip()
    if not ctx:
        return user_input
    block = "[Game context]\n" + ctx
    if isinstance(user_input, str):
        return block + "\n\n" + user_input if user_input else block
    if isinstance(user_input, list):
        return [{"role": "user", "content": block}] + list(user_input)
    return user_input



class XAIError(Exception):
    def __init__(self, message: str, status: int | None = None):
        super().__init__(message)
        self.status = status
        self.message = message


def response_tools(*, web_search: bool = True, x_search: bool = False) -> list[dict]:
    """Build xAI server-side tools list for POST /v1/responses (omit disabled)."""
    tools: list[dict] = []
    if web_search:
        tools.append({"type": "web_search"})
    if x_search:
        tools.append({"type": "x_search"})
    return tools


def post_response(
    *,
    api_key: str,
    model: str | None = None,
    api_base: str | None = None,
    input: Any = None,
    previous_response_id: str | None = None,
    system: str | None = None,
    tools: list[dict] | None = None,
    timeout: float = 600.0,
) -> dict:
    base = str(api_base or DEFAULT_BASE).rstrip("/")
    url = base + "/responses"
    body: dict[str, Any] = {
        "model": model or DEFAULT_MODEL,
        "input": input,
        "store": True,
    }
    # Always send instructions when provided — including resumed turns — so game
    # context stays current (coords/zone change between messages).
    if system:
        body["instructions"] = system
    if previous_response_id:
        body["previous_response_id"] = previous_response_id
    if tools:
        body["tools"] = tools

    data = json.dumps(body).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=data,
        method="POST",
        headers={
            "Content-Type": "application/json",
            "Authorization": "Bearer " + api_key,
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
        err = XAIError(api_error_message(status, parsed, raw), status=status)
        raise err from None
    except urllib.error.URLError as e:
        raise XAIError(f"xAI API network error: {e.reason}") from e

    try:
        parsed = json.loads(raw)
    except json.JSONDecodeError:
        raise XAIError("xAI API returned non-JSON") from None
    if not isinstance(parsed, dict):
        raise XAIError("xAI API returned non-JSON")
    text = extract_text(parsed)
    rid = parsed.get("id") or ""
    if not rid and not text:
        raise XAIError("xAI API returned an empty response")
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
    tools: list[dict] | None = None,
    on_progress: Callable[[], None] | None = None,
    timeout: float = 600.0,
) -> dict:
    key = api_key or os.environ.get("XAI_API_KEY") or ""
    if not key:
        raise XAIError(
            'Missing xAI API key. Set the XAI_API_KEY environment variable or "apiKey" in bridge_py/config.json.'
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
        user_input = as_user_input(input)
        try:
            return post_response(
                api_key=key,
                model=model,
                api_base=api_base,
                input=user_input,
                previous_response_id=previous_response_id or None,
                system=system,
                tools=tools,
                timeout=timeout,
            )
        except XAIError as err:
            if not previous_response_id or not is_previous_response_error(err):
                raise
            fallback = to_input_messages(history, input)
            return post_response(
                api_key=key,
                model=model,
                api_base=api_base,
                input=fallback if fallback else user_input,
                previous_response_id=None,
                system=system,
                tools=tools,
                timeout=timeout,
            )
    finally:
        stop.set()
        if beat:
            beat.cancel()
