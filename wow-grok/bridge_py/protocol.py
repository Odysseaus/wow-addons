"""Pure protocol helpers for the WoWGrok bridge (ported from bridge/protocol.js).

Strip records in, Lua slot files out, folder/permission/dedup rules.
No I/O, no config, no process state — unit-tested directly.
"""
from __future__ import annotations

import os
import re
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

MONTH_MS = 30 * 24 * 3600 * 1000


def from_hex(hex_str: str | None) -> str:
    try:
        return bytes.fromhex(hex_str or "").decode("utf-8")
    except (ValueError, UnicodeDecodeError):
        return ""


def pad3(n: int) -> str:
    return str(n).zfill(3)


def slot_number(id_: int, slots: int) -> int:
    return ((id_ - 1) % slots) + 1


def chat_key(job: dict) -> str:
    return f"{job.get('session') or ''}:{job.get('chat') or 'default'}"


def sess_key(job: dict) -> str:
    chat = job.get("chat")
    return f"chat:{chat}" if chat else chat_key(job)


def already_handled(state: dict, job: dict) -> bool:
    key = job.get("session") or ""
    h = (state.get("handled") or {}).get(key)
    if not h:
        return key == "" and job.get("id", 0) <= state.get("lastId", 0)
    jid = job["id"]
    return bool(h.get(jid) or h.get(str(jid)))


def mark_handled(state: dict, job: dict, now: int | None = None) -> None:
    if now is None:
        now = int(time.time() * 1000)
    key = job.get("session") or ""
    handled = state.setdefault("handled", {})
    h = handled.setdefault(key, {})
    h[job["id"]] = 1
    ids = list(h.keys())
    if len(ids) > 1000:
        for k in ids[: len(ids) - 1000]:
            del h[k]
    state["lastId"] = max(state.get("lastId", 0), job["id"])
    state.setdefault("seen", {})[key] = now


def prune_stale(
    state: dict,
    transcripts: dict | None,
    now: int | None = None,
    max_age_ms: int = MONTH_MS,
) -> int:
    if now is None:
        now = int(time.time() * 1000)
    removed = 0
    state.setdefault("seen", {})
    handled = state.setdefault("handled", {})
    for key in list(handled.keys()):
        if key == "":
            continue
        if key not in state["seen"]:
            state["seen"][key] = now
            continue
        if now - state["seen"][key] > max_age_ms:
            del handled[key]
            del state["seen"][key]
            removed += 1
    for key in list(state["seen"].keys()):
        if key not in handled and now - state["seen"][key] > max_age_ms:
            del state["seen"][key]
    if transcripts is not None:
        tokens = transcripts.setdefault("tokens", {})
        for tok in list(tokens.keys()):
            if now - tokens[tok] > max_age_ms:
                del tokens[tok]
                removed += 1
    return removed


def resolve_cwd(raw: str | None, base: str) -> str:
    p = str(raw or "").strip()
    if not p:
        return str(Path(base).resolve())
    if p == "~" or p.startswith("~/") or p.startswith("~\\"):
        home = str(Path.home())
        rest = p[1:]
        if rest.startswith("/") or rest.startswith("\\"):
            rest = rest[1:]
        p = os.path.join(home, rest) if rest else home
        return str(Path(p).resolve())
    if os.path.isabs(p):
        return str(Path(p).resolve())
    return str((Path(base) / p).resolve())


def same_folder(a: str | None, b: str | None) -> bool:
    return os.path.normcase(str(Path(a or "").resolve())) == os.path.normcase(
        str(Path(b or "").resolve())
    )


def parse_flags(flags: str | None) -> dict:
    out: dict[str, Any] = {
        "newSession": False,
        "hello": False,
        "forget": False,
        "context": False,
        "allow": [],
    }
    for tok in str(flags or "").split(";"):
        if tok == "n":
            out["newSession"] = True
        elif tok == "h":
            out["hello"] = True
        elif tok == "d":
            out["forget"] = True
        elif tok == "c":
            out["context"] = True
        elif tok.startswith("allow="):
            out["allow"].extend(
                s for s in (x.strip() for x in tok[6:].split(",")) if s
            )
    return out


def jobs_from_strip(header_id: int, payload: str) -> list[dict]:
    jobs: list[dict] = []
    for rec in str(payload).split("\x1e"):
        p = rec.split("\x1f")
        if len(p) >= 7 and p[2].isdigit():
            flags = parse_flags(p[4])
            with_ctx = flags.get("context") and len(p) >= 8
            job = {
                "session": p[0],
                "chat": p[1],
                "id": int(p[2]),
                "cwd": p[3],
                **flags,
                "name": p[5],
                "text": "\x1f".join(p[7 if with_ctx else 6 :]),
                "via": "pixel",
            }
            if with_ctx:
                job["ctx"] = p[6]
            jobs.append(job)
        elif len(p) == 6 and p[2].isdigit():
            jobs.append(
                {
                    "session": p[0],
                    "chat": p[1],
                    "id": int(p[2]),
                    "cwd": p[3],
                    **parse_flags(p[4]),
                    "name": "",
                    "text": p[5],
                    "via": "pixel",
                }
            )
        elif len(p) == 4:
            jobs.append(
                {
                    "session": p[0],
                    "chat": "",
                    "id": header_id,
                    "cwd": p[1],
                    **parse_flags(p[2]),
                    "text": p[3],
                    "via": "pixel",
                }
            )
    return jobs


_OUTBOX_RE = re.compile(r'\["outbox"\]\s*=\s*\{([^}]*)\}')


def parse_outbox(src: str | None) -> dict | None:
    m = _OUTBOX_RE.search(str(src or ""))
    if not m:
        return None
    b = m.group(1)
    id_m = re.search(r'\["id"\]\s*=\s*(\d+)', b)
    if not id_m:
        return None
    id_ = int(id_m.group(1))
    if not id_:
        return None
    text_m = re.search(r'\["text"\]\s*=\s*"([0-9a-fA-F]*)"', b)
    cwd_m = re.search(r'\["cwd"\]\s*=\s*"([0-9a-fA-F]*)"', b)
    sess_m = re.search(r'\["session"\]\s*=\s*"([0-9a-zA-Z]*)"', b)
    chat_m = re.search(r'\["chat"\]\s*=\s*"([0-9a-zA-Z]*)"', b)
    job = {
        "id": id_,
        "session": (sess_m.group(1) if sess_m else "") or "",
        "chat": (chat_m.group(1) if chat_m else "") or "",
        "text": from_hex(text_m.group(1) if text_m else ""),
        "cwd": from_hex(cwd_m.group(1) if cwd_m else ""),
        "newSession": bool(re.search(r'\["newSession"\]\s*=\s*true', b)),
        "via": "reload",
    }
    ctx_m = re.search(r'\["ctx"\]\s*=\s*"([0-9a-fA-F]*)"', b)
    if ctx_m:
        job["ctx"] = from_hex(ctx_m.group(1))
    return job


def system_prompt(ctx: str | None, primer: str = "") -> str:
    """Build the xAI instructions / system prompt from game context.

    Primer is accepted for API parity with wow-ai but unused for now (empty).
    Empty context returns "" so injection is a no-op.
    """
    text = str(ctx or "").strip()
    if not text:
        return ""
    lines = [
        "The user is talking to you from inside World of Warcraft through the WoWGrok addon. They type in a small in-game window and your reply is shown there as plain text (markdown is not rendered), so keep replies compact and formatting simple.",
        "",
        "Their in-game situation when the message was written, as reported by the addon:",
        text,
        "",
        'Use this when the request is about the game or the character (questions, macros, addon code, gear advice); ignore it when the task is unrelated. Items, spells or quests the player shift-clicked into a message appear as [Name] in the text, with their tooltip in a "Linked from the game" block at the end of the message.',
    ]
    ref = str(primer or "").strip()
    if ref:
        lines.extend(
            [
                "",
                "Reference for writing addons and macros for this client. Follow it when the task is about WoW, and check anything it marks as uncertain against the Blizzard UI source it names:",
                "",
                ref,
            ]
        )
    return "\n".join(lines)


def rule_for(d: dict) -> str:
    name = d.get("tool_name") or "Unknown"
    if name == "Bash":
        inp = d.get("tool_input") or {}
        cmd = str(inp.get("command") or "").strip()
        parts = cmd.split()
        word = parts[0] if parts else ""
        if word and re.match(r"^[\w.\-]+$", word):
            return f"Bash({word}:*)"
        return "Bash"
    return name


def describe_tool_use(block: dict) -> str:
    inp = block.get("input") or {}

    def base(p: Any) -> str:
        return os.path.basename(str(p or "").replace("\\", "/"))

    name = block.get("name")
    if name == "Bash":
        return f"$ {str(inp.get('command') or '').split(chr(10))[0][:110]}"
    if name == "Read":
        return f"read {base(inp.get('file_path'))}"
    if name == "Edit":
        return f"edit {base(inp.get('file_path'))}"
    if name == "Write":
        return f"write {base(inp.get('file_path'))}"
    if name == "Grep":
        return f"grep {inp.get('pattern') or ''}"
    if name == "Glob":
        return f"glob {inp.get('pattern') or ''}"
    if name == "Agent":
        return f"agent: {inp.get('description') or ''}"
    if name == "WebSearch":
        return f"search: {inp.get('query') or ''}"
    if name == "WebFetch":
        return f"fetch {inp.get('url') or ''}"
    return str(name or "")


def lua_str(s: Any) -> str:
    if s is None:
        s = ""
    else:
        s = str(s)
    out: list[str] = ['"']
    for ch in s:
        o = ord(ch)
        if ch == "\\":
            out.append("\\\\")
        elif ch == '"':
            out.append('\\"')
        elif ch == "\r":
            continue
        elif ch == "\n":
            out.append("\\n")
        elif (0 <= o <= 0x08) or (0x0B <= o <= 0x1F) or o == 0x7F:
            out.append("\\" + str(o).zfill(3))
        else:
            out.append(ch)
    out.append('"')
    return "".join(out)


def lua_table(global_name: str, records: list, opts: dict | None = None) -> str:
    opts = opts or {}
    now = opts.get("now")
    if now is None:
        now = int(time.time() * 1000)
    iso = (
        datetime.fromtimestamp(now / 1000, tz=timezone.utc)
        .isoformat(timespec="milliseconds")
        .replace("+00:00", "Z")
    )
    lines = [
        "-- Written by the wow-grok bridge (bridge_py). Do not edit by hand.",
        f"{global_name} = {{",
        f"\tts = {lua_str(iso)},",
        f"\tnow = {now // 1000},",
        f"\tcwd = {lua_str(opts.get('cwd') or '')},",
        "\treplies = {",
    ]
    for r in records:
        lines.append("\t\t{")
        lines.append(f"\t\t\tchat = {lua_str(r.get('chat') or '')},")
        lines.append(f"\t\t\tid = {int(r.get('id') or 0)},")
        lines.append(f"\t\t\tstatus = {lua_str(r.get('status'))},")
        lines.append(f"\t\t\ttext = {lua_str(r.get('text'))},")
        lines.append(f"\t\t\tcwd = {lua_str(r.get('cwd') or '')},")
        lines.append(f"\t\t\tsession = {lua_str(r.get('session') or '')},")
        denied = r.get("denied")
        if isinstance(denied, list) and denied:
            lines.append(
                f"\t\t\tdenied = {{ {', '.join(lua_str(x) for x in denied)} }},"
            )
        lines.append("\t\t},")
    lines.append("\t},")
    restore = opts.get("restore")
    if restore:
        lines.append("\trestore = {")
        lines.append(f"\t\ttoken = {lua_str(restore.get('token'))},")
        lines.append("\t\tchats = {")
        for c in restore.get("chats") or []:
            lines.append("\t\t\t{")
            lines.append(f"\t\t\t\tid = {lua_str(c.get('id'))},")
            lines.append(f"\t\t\t\tname = {lua_str(c.get('name'))},")
            lines.append(f"\t\t\t\tcwd = {lua_str(c.get('cwd'))},")
            lines.append("\t\t\t\tmessages = {")
            for m in c.get("messages") or []:
                lines.append(
                    f"\t\t\t\t\t{{ role = {lua_str(m.get('role'))}, "
                    f"id = {int(m.get('id') or 0)}, "
                    f"t = {int(m.get('t') or 0)}, "
                    f"text = {lua_str(m.get('text'))} }},"
                )
            lines.append("\t\t\t\t},")
            lines.append("\t\t\t},")
        lines.append("\t\t},")
        lines.append("\t},")
    lines.append("}")
    lines.append("")
    return "\n".join(lines)


def _build_silent_wav() -> bytes:
    rate = 8000
    samples = 80
    b = bytearray(44 + samples)
    b[0:4] = b"RIFF"
    b[4:8] = (36 + samples).to_bytes(4, "little")
    b[8:12] = b"WAVE"
    b[12:16] = b"fmt "
    b[16:20] = (16).to_bytes(4, "little")
    b[20:22] = (1).to_bytes(2, "little")
    b[22:24] = (1).to_bytes(2, "little")
    b[24:28] = rate.to_bytes(4, "little")
    b[28:32] = rate.to_bytes(4, "little")
    b[32:34] = (1).to_bytes(2, "little")
    b[34:36] = (8).to_bytes(2, "little")
    b[36:40] = b"data"
    b[40:44] = samples.to_bytes(4, "little")
    for i in range(44, 44 + samples):
        b[i] = 128
    return bytes(b)


SILENT_WAV = _build_silent_wav()
