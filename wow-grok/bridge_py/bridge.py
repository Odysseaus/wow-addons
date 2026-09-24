"""WoW Grok bridge main loop (ported from bridge/bridge.js).

OUT  capture (mac/win) pixel strip -> jobs  (fallback: SavedVariables outbox)
RUN  xAI Grok API per chat, up to maxParallel
IN   write Inbox.lua + WoWGrok_S### slot files + signal wavs
"""
from __future__ import annotations

import argparse
import json
import os
import signal
import subprocess
import sys
import threading
import time
from pathlib import Path
from typing import Any

from . import config as cfgmod
from . import protocol as P
from . import ssl_certs as _ssl_certs
from . import xai

try:
    _ssl_certs.configure()
except Exception:
    pass

HERE = Path(__file__).resolve().parent
REPO = HERE.parent

# capture_mac exits with this when Screen Recording / TCC is unavailable.
CAPTURE_PERMISSION_EXIT = 42


def capture_spawn_blocked(cap: dict) -> str | None:
    """Return a short reason if capture must not spawn, else None."""
    if not cap.get("enabled"):
        return "disabled"
    if cap.get("permissionPaused"):
        return "permissionPaused"
    return None


def mark_capture_permission_paused(cfg: dict) -> None:
    """Persist capture.permissionPaused so later launches never spawn capture.

    Cleared only when the user sets capture.permissionPaused to false in
    config.json (Quit + edit). Do not clear on probe=granted (false positives).
    """
    cap = cfg.setdefault("capture", {})
    if cap.get("permissionPaused"):
        return
    cap["permissionPaused"] = True
    try:
        cfgmod.save_config(cfg)
    except Exception:  # noqa: BLE001
        pass



def _notify_mac_screen_recording(msg: str) -> str:
    """One guided dialog on the primary display. Returns ``quit`` or ``continue``."""
    if sys.platform != "darwin":
        return "continue"
    try:
        from . import tk_util

        return tk_util.show_screen_recording_dialog(
            "Screen capture is paused so macOS stops asking repeatedly.\n\n"
            f"{msg}\n\n"
            "1. System Settings → Privacy & Security → Screen Recording "
            "(or Screen & System Audio Recording)\n"
            "2. Turn WoWGrok ON\n"
            "3. Click Quit WoWGrok, then reopen from /Applications\n\n"
            "SavedVariables /reload still works without capture."
        )
    except Exception:
        return "continue"




def inside_repo(dir_path: str) -> bool:
    try:
        Path(dir_path).resolve().relative_to(REPO)
        return True
    except ValueError:
        return False


def read_json(path: Path, fallback: dict) -> dict:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return dict(fallback)


def atomic_write(file: Path, content: str | bytes) -> None:
    tmp = Path(str(file) + ".tmp")
    if isinstance(content, bytes):
        tmp.write_bytes(content)
    else:
        tmp.write_text(content, encoding="utf-8")
    tmp.replace(file)


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(
        prog="wow-grok",
        description=(
            "Runs the WoW Grok bridge. Chats without a folder of their own work in "
            "<dir>, or in the folder you started it from, or in defaultCwd from config."
        ),
    )
    ap.add_argument("--project", help="default folder for chats")
    ap.add_argument("--once", action="store_true", help="handle one SavedVariables prompt and exit")
    ap.add_argument("--inject", help="pretend the strip said this and exit when done")
    ap.add_argument("--wow", help="WoW client or AddOns path (first-run / override)")
    ap.add_argument("--headless", action="store_true", help="no first-run UI; fail if config incomplete")
    ap.add_argument("--no-supervisor", action="store_true", help="internal: already under supervisor")
    args = ap.parse_args(argv)

    # First-run / config
    from .first_run import ensure_first_run_config

    cfg = ensure_first_run_config(headless=args.headless or not _can_gui(), wow=args.wow)

    state_file = cfgmod.state_path()
    log_file = cfgmod.log_path()
    transcript_file = cfgmod.transcripts_path()

    state = read_json(
        state_file,
        {"lastId": 0, "sessions": {}, "handled": {}, "history": {}},
    )
    state.setdefault("handled", {})
    state.setdefault("sessions", {})
    state.setdefault("history", {})
    # Expand legacy high-water numbers
    for k, v in list(state["handled"].items()):
        if isinstance(v, (int, float)):
            state["handled"][k] = {i: 1 for i in range(1, int(v) + 1)}

    transcripts = read_json(transcript_file, {"chats": {}, "tokens": {}})
    transcripts.setdefault("chats", {})
    transcripts.setdefault("tokens", {})
    if P.prune_stale(state, transcripts):
        _save(state_file, state)
        _save(transcript_file, transcripts)

    # Default cwd
    cwd_now = os.getcwd()
    if args.project:
        default_cwd = str(Path(args.project).resolve())
        default_src = "--project"
    elif os.environ.get("WOW_GROK_PROJECT"):
        default_cwd = str(Path(os.environ["WOW_GROK_PROJECT"]).resolve())
        default_src = "WOW_GROK_PROJECT"
    elif not inside_repo(cwd_now):
        default_cwd = str(Path(cwd_now).resolve())
        default_src = "started here"
    else:
        default_cwd = str(Path(cfg.get("defaultCwd") or cwd_now).resolve())
        default_src = "config.json"

    slots = int(cfg.get("slots") or 200)
    max_parallel = int(cfg.get("maxParallel") or 3)
    cap = {
        "enabled": True,
        "processName": "WowB",
        "cellPx": 4,
        "cellsPerRow": 200,
        "maxRows": 48,
        "intervalMs": 250,
        **(cfg.get("capture") or {}),
    }
    # Example placeholder WowB: re-detect from addonDir client (Mac Forever is not WowB).
    if sys.platform == "darwin" and cap.get("processName") == "WowB" and cfg.get("addonDir"):
        try:
            from . import setup_detect

            client = Path(cfg["addonDir"]).resolve().parent.parent
            cap["processName"] = setup_detect.detect_process_name(client)
        except Exception:
            pass
    act_max = int(cfg.get("actMax") or 60)
    presence_max = int(cfg.get("presenceMax") or 2000)
    poll_ms = int(cfg.get("pollMs") or 750)
    progress_write_ms = int(cfg.get("progressWriteMs") or 3000)
    timeout_ms = int(cfg.get("timeoutMs") or 1_800_000)

    api_key = cfgmod.resolve_api_key(cfg)
    # Never log the key — only the source label
    key_src = cfgmod.api_key_source(cfg)

    forgotten: set[str] = set()
    pending_restore: dict | None = None
    running: dict[str, dict] = {}
    queued: dict[str, dict] = {}
    live: dict[str, dict] = {}
    last_publish = 0.0
    publish_lock = threading.Lock()
    stop_event = threading.Event()
    last_mtime = 0.0
    warned_no_addon = {"v": False}
    capture_proc: list[subprocess.Popen | None] = [None]

    def log(*parts: object) -> None:
        line = f"[{time.strftime('%Y-%m-%dT%H:%M:%S')}] {' '.join(str(p) for p in parts)}"
        print(line, flush=True)
        try:
            with open(log_file, "a", encoding="utf-8") as f:
                f.write(line + "\n")
        except OSError:
            pass

    def save_state() -> None:
        _save(state_file, state)

    def save_transcripts() -> None:
        try:
            _save(transcript_file, transcripts)
        except OSError as e:
            log("could not save transcripts:", e)

    def set_context(job: dict) -> None:
        """Store (or clear) game context from an inbound strip/outbox job."""
        if "ctx" not in job:
            return
        text = str(job.get("ctx") or "").replace("\r", "").strip()[:2000]
        prev = ((state.get("context") or {}).get("text")) or ""
        if text == prev:
            return
        if text:
            state["context"] = {
                "text": text,
                "at": int(time.time() * 1000),
                "session": job.get("session") or "",
            }
        else:
            state["context"] = None
        save_state()
        who = ""
        if text:
            for line in text.split("\n"):
                if line.lower().startswith("character:"):
                    who = line[:100]
                    break
            if not who:
                who = (text.split("\n")[0] if text else "")[:100]
        tag = f"#{job.get('id')}"
        if job.get("session"):
            tag += "@" + str(job["session"])
        log(f"{tag} game context {'updated: ' + who if text else 'cleared'}")

    def game_context() -> str:
        if cfg.get("gameContext") is False:
            return ""
        ctx = state.get("context") or {}
        return str(ctx.get("text") or "") if isinstance(ctx, dict) else ""

    def resolve_cwd(raw: str | None) -> str:
        return P.resolve_cwd(raw, default_cwd)

    def slot_file(global_name: str, records: list) -> str:
        return P.lua_table(
            global_name,
            records,
            {
                "cwd": default_cwd,
                "restore": pending_restore,
                "capturePaused": bool(cap.get("permissionPaused")),
            },
        )

    def addon_installed() -> bool:
        return (Path(cfg["addonDir"]) / "WoWGrok" / "WoWGrok.toc").exists()

    def slots_installed() -> bool:
        return (Path(cfg["addonDir"]) / "WoWGrok_S001" / "Inbox.lua").exists()

    def publish_now() -> None:
        nonlocal last_publish, pending_restore
        last_publish = time.time() * 1000
        records = list(live.values())[-30:]
        try:
            atomic_write(Path(cfg["inboxFile"]), slot_file("WoWGrok_Inbox", records))
        except OSError as e:
            if not warned_no_addon["v"]:
                warned_no_addon["v"] = True
                log(
                    f"publish: cannot write {cfg['inboxFile']} ({e}); "
                    "addon not installed? copy addon/WoWGrok into AddOns, then restart WoW"
                )
            return
        if not slots_installed():
            return
        body = slot_file("WoWGrok_SlotData", records)
        for i in range(1, slots + 1):
            try:
                atomic_write(
                    Path(cfg["addonDir"]) / f"WoWGrok_S{P.pad3(i)}" / "Inbox.lua",
                    body,
                )
            except OSError:
                pass
        if pending_restore:
            pending_restore["published"] = pending_restore.get("published", 0) + 1
            if pending_restore["published"] >= 3:
                pending_restore = None

    def publish(key: str, record: dict, urgent: bool = False) -> None:
        with publish_lock:
            live[key] = record
            if urgent:
                publish_now()
                return
            wait = progress_write_ms - (time.time() * 1000 - last_publish)
            if wait <= 0:
                publish_now()
            else:
                threading.Timer(wait / 1000.0, publish_now).start()

    def signal_wav(kind: str, id_: int, on: bool) -> None:
        slot = P.slot_number(id_, slots)
        file = Path(cfg["addonDir"]) / "WoWGrok" / kind / f"{P.pad3(slot)}.wav"
        try:
            atomic_write(file, P.SILENT_WAV if on else b"")
        except OSError:
            pass

    def act_file(id_: int, k: int) -> Path:
        return (
            Path(cfg["addonDir"])
            / "WoWGrok"
            / "act"
            / P.pad3(P.slot_number(id_, slots))
            / f"{str(k).zfill(2)}.wav"
        )

    def reset_beats(id_: int) -> None:
        for k in range(1, act_max + 1):
            try:
                atomic_write(act_file(id_, k), b"")
            except OSError:
                pass

    def beat(job: dict) -> None:
        job["beats"] = job.get("beats", 0) + 1
        if job["beats"] > act_max:
            return
        try:
            atomic_write(act_file(job["id"], job["beats"]), P.SILENT_WAV)
        except OSError:
            pass

    def presence_beat() -> None:
        """Flip presence/NNNN.wav so the addon can hear the bridge.

        The addon binary-searches for a contiguous valid prefix 1..k. We must
        rewrite the whole prefix each beat — if state.presence advances after
        files were wiped (or after a wrap emptied low numbers), writing only
        the current k leaves 1..(k-1) empty and FindPresenceHead returns 0.
        """
        presence_dir = Path(cfg["addonDir"]) / "WoWGrok" / "presence"
        if not presence_dir.exists():
            return
        state["presence"] = ((state.get("presence") or 0) % presence_max) + 1
        k = state["presence"]
        for i in range(1, k + 1):
            try:
                atomic_write(presence_dir / f"{str(i).zfill(4)}.wav", P.SILENT_WAV)
            except OSError:
                pass
        for j in range(1, 51):
            n = ((k - 1 + j) % presence_max) + 1
            try:
                atomic_write(presence_dir / f"{str(n).zfill(4)}.wav", b"")
            except OSError:
                pass
        save_state()

    def note_message(job: dict, role: str, text: str) -> None:
        if not job.get("chat"):
            return
        if role == "user":
            forgotten.discard(job["chat"])
        elif job["chat"] in forgotten:
            return
        c = transcripts["chats"].setdefault(
            job["chat"],
            {"id": job["chat"], "name": "", "cwd": job.get("cwd"), "messages": []},
        )
        if job.get("name"):
            c["name"] = job["name"]
        if job.get("cwd"):
            c["cwd"] = job["cwd"]
        c["messages"].append(
            {
                "role": role,
                "text": str(text or "")[:4000],
                "id": job["id"],
                "t": int(time.time()),
            }
        )
        while len(c["messages"]) > 200:
            c["messages"].pop(0)
        c["updated"] = int(time.time() * 1000)
        save_transcripts()

    def maybe_offer_restore(job: dict) -> None:
        nonlocal pending_restore
        if not job.get("session") or transcripts["tokens"].get(job["session"]):
            return
        transcripts["tokens"][job["session"]] = int(time.time() * 1000)
        chats = sorted(
            (
                c
                for c in transcripts["chats"].values()
                if c.get("id") != job.get("chat") and c.get("messages")
            ),
            key=lambda c: c.get("updated") or 0,
            reverse=True,
        )[:16]
        mapped = [
            {
                "id": c["id"],
                "name": c.get("name"),
                "cwd": c.get("cwd"),
                "messages": [
                    {**m, "text": str(m.get("text", ""))[:2000]}
                    for m in (c.get("messages") or [])[-40:]
                ],
            }
            for c in chats
        ]
        save_transcripts()
        if mapped:
            pending_restore = {"token": job["session"], "chats": mapped}
            log(f"new addon session {job['session']}: offering {len(mapped)} chat(s) to restore")

    def forget_chat(job: dict) -> None:
        nonlocal pending_restore
        if not job.get("chat"):
            return
        had = job["chat"] in transcripts["chats"]
        transcripts["chats"].pop(job["chat"], None)
        forgotten.add(job["chat"])
        sk = P.sess_key(job)
        ck = P.chat_key(job)
        state["sessions"].pop(sk, None)
        state["sessions"].pop(ck, None)
        if state.get("sessionCwd"):
            state["sessionCwd"].pop(sk, None)
        if state.get("history"):
            state["history"].pop(sk, None)
        if pending_restore:
            pending_restore["chats"] = [
                c for c in pending_restore["chats"] if c.get("id") != job["chat"]
            ]
        save_transcripts()
        log(
            f"#{job['id']}{'@' + job['session'] if job.get('session') else ''} "
            f"forgot chat {job['chat']}{'' if had else ' (nothing stored)'}"
        )

    def finish(job: dict, status: str, text: str, session: str | None = None) -> None:
        key = P.chat_key(job)
        running.pop(key, None)
        if status == "done":
            note_message(job, "assistant", text)
        publish(
            key,
            {
                "chat": job.get("chat") or "",
                "id": job["id"],
                "status": status,
                "text": text,
                "cwd": job.get("cwd") or "",
                "session": session or "",
            },
            urgent=True,
        )
        if status == "done":
            signal_wav("sig", job["id"], True)
        P.mark_handled(state, job)
        save_state()
        drain_queue()
        if args.once or args.inject is not None:
            if not running and not queued:
                stop_event.set()

    def drain_queue() -> None:
        for key, job in list(queued.items()):
            if len(running) >= max_parallel:
                break
            if key in running:
                continue
            queued.pop(key, None)
            run_job(job)

    def run_job(job: dict) -> None:
        key = P.chat_key(job)
        cwd = resolve_cwd(job.get("cwd"))
        job["cwd"] = cwd
        tag = f"#{job['id']}{'@' + job['session'] if job.get('session') else ''}"
        signal_wav("sig", job["id"], False)
        reset_beats(job["id"])
        signal_wav("ack", job["id"], True)
        if not Path(cwd).exists():
            log(f"{tag} cwd does not exist: {cwd}")
            finish(
                job,
                "error",
                f"Folder does not exist: {cwd}\nPaths are relative to {default_cwd}.\n"
                "Use /wow-grok cd <folder> to pick one, or /wow-grok cd alone for the default.",
            )
            return

        skey = P.sess_key(job)
        if job.get("newSession"):
            state["sessions"].pop(skey, None)
            state["sessions"].pop(key, None)
            state.setdefault("history", {}).pop(skey, None)
        prev_cwd = (state.get("sessionCwd") or {}).get(skey)
        if prev_cwd and not P.same_folder(prev_cwd, cwd) and state["sessions"].get(skey):
            log(f"{tag} folder changed ({prev_cwd} -> {cwd}): new conversation")
            state["sessions"].pop(skey, None)
            state["sessions"].pop(key, None)
            state.setdefault("history", {}).pop(skey, None)

        state.setdefault("sessionCwd", {})[skey] = cwd
        note_message(job, "user", job.get("text") or "")
        publish(
            key,
            {
                "chat": job.get("chat") or "",
                "id": job["id"],
                "status": "working",
                "text": "Thinking…",
                "cwd": cwd,
                "session": state["sessions"].get(skey) or "",
            },
            urgent=True,
        )
        abort = {"flag": False}
        running[key] = {"job": job, "abort": abort}
        log(f"{tag} -> grok ({cfg.get('model') or xai.DEFAULT_MODEL}) in {cwd}")

        def worker() -> None:
            try:
                hist = list(state.setdefault("history", {}).get(skey) or [])
                prev_id = state["sessions"].get(skey)

                def on_progress() -> None:
                    if abort["flag"]:
                        return
                    beat(job)
                    publish(
                        key,
                        {
                            "chat": job.get("chat") or "",
                            "id": job["id"],
                            "status": "working",
                            "text": "Thinking…",
                            "cwd": cwd,
                            "session": state["sessions"].get(skey) or "",
                        },
                    )

                system = P.system_prompt(game_context())
                result = xai.chat(
                    api_key=api_key,
                    model=cfg.get("model"),
                    api_base=cfg.get("apiBase"),
                    input=job.get("text") or "",
                    previous_response_id=prev_id,
                    system=system or None,
                    history=hist,
                    on_progress=on_progress,
                    timeout=timeout_ms / 1000.0,
                )
                if abort["flag"]:
                    return
                rid = result.get("id") or ""
                text = result.get("text") or ""
                if rid:
                    state["sessions"][skey] = rid
                hist.append({"role": "user", "content": job.get("text") or ""})
                hist.append({"role": "assistant", "content": text})
                while len(hist) > 40:
                    hist.pop(0)
                state.setdefault("history", {})[skey] = hist
                save_state()
                finish(job, "done", text, session=rid)
            except Exception as e:  # noqa: BLE001
                if abort["flag"]:
                    return
                log(f"{tag} error: {e}")
                finish(job, "error", str(e))

        threading.Thread(target=worker, daemon=True).start()

    def find_handled_reply_text(job: dict) -> str | None:
        """Return assistant text for an already-handled job from transcripts."""
        chat_id = job.get("chat") or ""
        jid = int(job.get("id") or 0)
        c = (transcripts.get("chats") or {}).get(chat_id) or {}
        msgs = list(c.get("messages") or [])
        # Prefer assistant row with same id; else assistant after user with that id.
        for m in msgs:
            if m.get("role") == "assistant" and int(m.get("id") or 0) == jid:
                return str(m.get("text") or "")
        for i, m in enumerate(msgs):
            if m.get("role") == "user" and int(m.get("id") or 0) == jid:
                for n in msgs[i + 1 :]:
                    if n.get("role") == "assistant":
                        return str(n.get("text") or "")
                break
        # Fallback: state history pairs (no ids) — last assistant for this sess key
        sk = P.sess_key(job)
        hist = (state.get("history") or {}).get(sk) or []
        for m in reversed(hist):
            if m.get("role") == "assistant":
                return str(m.get("content") or m.get("text") or "")
        return None

    def republish_handled_reply(job: dict) -> None:
        """Re-write Inbox/slots for an already-handled outbox id (stuck pending)."""
        text = find_handled_reply_text(job)
        if text is None:
            text = (
                "(WoWGrok already handled this message earlier; reply was missing "
                "from Inbox — try sending again if this is empty.)"
            )
        key = P.chat_key(job)
        publish(
            key,
            {
                "chat": job.get("chat") or "",
                "id": job["id"],
                "status": "done",
                "text": text,
                "cwd": job.get("cwd") or "",
                "session": (state.get("sessions") or {}).get(P.sess_key(job))
                or (state.get("sessions") or {}).get(key)
                or "",
            },
            urgent=True,
        )
        signal_wav("sig", job["id"], True)
        log(
            f"re-publish handled #{job['id']}"
            f"{'@' + job['session'] if job.get('session') else ''} for Inbox"
        )

    def submit(job: dict) -> None:
        if "ctx" in job:
            set_context(job)
        if P.already_handled(state, job):
            republish_handled_reply(job)
            return
        if job.get("forget"):
            P.mark_handled(state, job)
            forget_chat(job)
            save_state()
            signal_wav("ack", job["id"], True)
            return
        if job.get("hello"):
            P.mark_handled(state, job)
            save_state()
            signal_wav("ack", job["id"], True)
            maybe_offer_restore(job)
            publish_now()
            log(
                f"hello from session {job.get('session')}"
                f"{' (restore offered)' if pending_restore else ''}"
            )
            return
        key = P.chat_key(job)
        cur = running.get(key)
        if cur and cur["job"]["id"] == job["id"]:
            return
        q = queued.get(key)
        if q and q["id"] == job["id"]:
            return
        if cur or len(running) >= max_parallel:
            queued[key] = job
            log(
                f"#{job['id']}{'@' + job['session'] if job.get('session') else ''} queued "
                f"({'chat busy' if cur else str(len(running)) + ' running'})"
            )
            return
        run_job(job)

    def poll_saved_variables() -> None:
        nonlocal last_mtime
        sv = Path(cfg.get("savedVariablesFile") or "")
        if not sv.exists():
            return
        try:
            mtime = sv.stat().st_mtime
        except OSError:
            return
        if mtime == last_mtime:
            return
        last_mtime = mtime
        try:
            src = sv.read_text(encoding="utf-8", errors="replace")
        except OSError:
            return
        job = P.parse_outbox(src)
        if job:
            submit(job)

    # Screen-recording UI must run on the main thread (Tk is not thread-safe).
    screen_ui: dict[str, Any] = {
        "pending": False,
        "msg": "",
        "result": "continue",
        "event": threading.Event(),
    }

    def start_capture() -> None:
        blocked = capture_spawn_blocked(cap)
        if blocked == "disabled":
            return
        if blocked == "permissionPaused":
            log(
                "capture: permissionPaused — not spawning (presence/Connect + "
                "reload chat). Capture stays off until a real resume smoke succeeds "
                "after you enable Screen Recording and clear the flag, then Quit+reopen."
            )
            try:
                publish_now()
            except Exception:  # noqa: BLE001
                pass
            return
        # Explicit clear of permissionPaused is not enough — require real smoke.
        smoke_ok = True
        if sys.platform == "darwin":
            try:
                from .capture_mac import resume_smoke_ok

                smoke_ok = bool(resume_smoke_ok())
            except Exception:  # noqa: BLE001
                smoke_ok = False
        if not smoke_ok:
            mark_capture_permission_paused(cfg)
            cap["permissionPaused"] = True
            log(
                "capture: resume smoke failed — re-set permissionPaused, not spawning "
                "(probe=granted alone is not enough)"
            )
            try:
                publish_now()
            except Exception:  # noqa: BLE001
                pass
            return
        cap_args = [
            "--cell",
            str(cap["cellPx"]),
            "--cells",
            str(cap["cellsPerRow"]),
            "--max-rows",
            str(cap["maxRows"]),
            "--interval-ms",
            str(cap["intervalMs"]),
            "--process-name",
            str(cap["processName"]),
        ]
        frozen = getattr(sys, "frozen", False)
        if sys.platform == "darwin":
            if frozen:
                cmd = [sys.executable, "--run-capture-mac", *cap_args]
            else:
                cmd = [sys.executable, "-m", "bridge_py.capture_mac", *cap_args]
        elif sys.platform == "win32":
            if frozen:
                cmd = [sys.executable, "--run-capture-win", *cap_args]
            else:
                cmd = [sys.executable, "-m", "bridge_py.capture_win", *cap_args]
        else:
            log("capture: unsupported platform; SavedVariables poll only")
            return

        def reader(proc: subprocess.Popen) -> None:
            assert proc.stdout
            for line in proc.stdout:
                line = line.strip()
                if not line:
                    continue
                try:
                    ev = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if ev.get("info"):
                    log("capture:", ev["info"])
                    continue
                if ev.get("warn"):
                    log("capture:", ev["warn"])
                    continue
                if ev.get("permission") == "screen_recording" or ev.get("permission") == "screen_recording_denied":
                    log("capture permission:", ev.get("error") or "Screen Recording required")
                    continue
                if ev.get("error"):
                    log("capture error:", ev["error"])
                    continue
                # Frame payload: {id, payload} or jobs
                header_id = int(ev.get("id") or 0)
                payload = ev.get("payload") or ev.get("text") or ""
                if payload or header_id:
                    for job in P.jobs_from_strip(header_id, payload):
                        submit(job)

        def loop() -> None:
            guided = {"shown": False}
            # Non-permission exit flap backoff (5s → 10s → 20s … cap 60s).
            restart_delay = 5.0
            while not stop_event.is_set():
                try:
                    proc = subprocess.Popen(
                        cmd,
                        stdout=subprocess.PIPE,
                        stderr=subprocess.PIPE,
                        text=True,
                        bufsize=1,
                    )
                    capture_proc[0] = proc
                    t = threading.Thread(target=reader, args=(proc,), daemon=True)
                    t.start()
                    proc.wait()
                    rc = proc.returncode
                    capture_proc[0] = None
                    if stop_event.is_set():
                        break
                    if rc == CAPTURE_PERMISSION_EXIT:
                        mark_capture_permission_paused(cfg)
                        cap["permissionPaused"] = True
                        log(
                            "capture paused (Screen Recording); saved "
                            "capture.permissionPaused=true — will not spawn capture "
                            "on next launch. Presence / Connect keep running without "
                            "the pixel path. Clear the flag in config.json after "
                            "enabling Screen Recording, then Quit+reopen."
                        )
                        if not guided["shown"]:
                            guided["shown"] = True
                            screen_ui["msg"] = (
                                "WoWGrok could not use Screen Recording in this process."
                            )
                            screen_ui["result"] = "continue"
                            screen_ui["event"].clear()
                            screen_ui["pending"] = True
                            # Wait for main thread to show the dialog
                            screen_ui["event"].wait(timeout=600)
                            if screen_ui.get("result") == "quit":
                                stop_event.set()
                        break
                    log(
                        f"capture exited ({rc}); restarting in {int(restart_delay)} s"
                    )
                    time.sleep(restart_delay)
                    restart_delay = min(restart_delay * 2, 60.0)
                except Exception as e:  # noqa: BLE001
                    log("capture spawn error:", e)
                    time.sleep(restart_delay)
                    restart_delay = min(restart_delay * 2, 60.0)

        threading.Thread(target=loop, daemon=True).start()

    # Banner
    cap_proc = (
        "capture_mac"
        if sys.platform == "darwin"
        else "capture_win"
        if sys.platform == "win32"
        else "none"
    )
    print("WoW Grok bridge (Python)")
    print(f"  config   : {cfgmod.config_path()}")
    print(f"  addonDir : {cfg.get('addonDir')}")
    print(f"  project  : {default_cwd}  ({default_src})")
    print(f"  model    : {cfg.get('model') or xai.DEFAULT_MODEL}")
    print(f"  api key  : {key_src}")
    if not cap.get("enabled"):
        cap_label = "off"
    elif cap.get("permissionPaused"):
        cap_label = (
            "paused — presence/Connect + reload chat (capture off until smoke ok)"
        )
    else:
        cap_label = (
            "on (" + cap_proc + ", " + str(cap["processName"]) + ", "
            + str(cap["cellsPerRow"]) + "x" + str(cap["maxRows"]) + " cells of "
            + str(cap["cellPx"]) + "px)"
        )
    print(f"  capture  : {cap_label}")
    print(f"  slots    : {slots}  parallel={max_parallel}")
    if cfg.get("gameContext") is False:
        print("  context  : off (gameContext in config.json)")
    else:
        ctx_preview = game_context()
        if ctx_preview:
            who = ""
            for line in ctx_preview.split("\n"):
                if line.lower().startswith("character:"):
                    who = line[:100]
                    break
            if not who:
                who = ctx_preview.split("\n")[0][:100]
            print(f"  context  : {who}")
        else:
            print(
                "  context  : none yet (the addon sends it with its hello; "
                "/wow-grok context in game)"
            )
    if not addon_installed():
        print(
            "  WARNING  : WoWGrok.toc not found under addonDir — "
            "re-run the WoWGrok app to install the addon, then fully quit/relaunch WoW"
        )
    elif not slots_installed():
        print(
            "  WARNING  : reply slots missing — "
            "re-run the WoWGrok app to install slots, then fully quit/relaunch WoW"
        )

    if args.inject is not None:
        submit(
            {
                "session": "",
                "chat": "inject",
                "id": max(state.get("lastId", 0) + 1, 1),
                "cwd": "",
                "newSession": False,
                "hello": False,
                "forget": False,
                "allow": [],
                "name": "inject",
                "text": args.inject,
                "via": "inject",
            }
        )
    else:
        poll_saved_variables()
        if cap.get("permissionPaused"):
            try:
                publish_now()
                log("inbox: advertised capturePaused=true for reload transport")
            except Exception:  # noqa: BLE001
                pass
        start_capture()
        presence_beat()

        def poll_loop() -> None:
            while not stop_event.is_set():
                poll_saved_variables()
                time.sleep(poll_ms / 1000.0)

        def presence_loop() -> None:
            interval = int(cfg.get("presenceIntervalMs") or 30000) / 1000.0
            while not stop_event.is_set():
                time.sleep(interval)
                if stop_event.is_set():
                    break
                presence_beat()

        threading.Thread(target=poll_loop, daemon=True).start()
        threading.Thread(target=presence_loop, daemon=True).start()

    def stop_capture() -> None:
        """Terminate capture child; wait ~3s then kill if needed; clear slot."""
        p = capture_proc[0]
        if p is None:
            return
        capture_proc[0] = None
        if p.poll() is not None:
            return
        try:
            p.terminate()
        except ProcessLookupError:
            return
        try:
            p.wait(timeout=3)
        except subprocess.TimeoutExpired:
            try:
                p.kill()
            except ProcessLookupError:
                pass
            try:
                p.wait(timeout=2)
            except subprocess.TimeoutExpired:
                pass

    def _kill_sibling_wowgrok_pids() -> None:
        """Best-effort: terminate other frozen WoWGrok PIDs (orphaned capture).

        Only targets processes whose command line contains ``sys.executable``.
        Skips this process and its parent (live supervisor) so Quit can exit
        cleanly; never touches unrelated apps.
        """
        if sys.platform != "darwin" or not getattr(sys, "frozen", False):
            return
        exe = sys.executable
        skip = {os.getpid(), os.getppid()}
        try:
            out = subprocess.check_output(
                ["pgrep", "-f", exe],
                text=True,
                stderr=subprocess.DEVNULL,
            )
        except (subprocess.CalledProcessError, FileNotFoundError, OSError):
            return
        for line in out.splitlines():
            line = line.strip()
            if not line.isdigit():
                continue
            pid = int(line)
            if pid in skip:
                continue
            try:
                os.kill(pid, signal.SIGTERM)
            except (ProcessLookupError, PermissionError, OSError):
                pass

    def on_sig(*_a: object) -> None:
        stop_event.set()
        stop_capture()

    def on_quit() -> None:
        stop_event.set()
        stop_capture()

    signal.signal(signal.SIGINT, on_sig)
    signal.signal(signal.SIGTERM, on_sig)

    if args.once or args.inject is not None:
        # Wait until idle or timeout
        deadline = time.time() + 120
        while not stop_event.is_set() and time.time() < deadline:
            if not running and not queued and (args.inject is None or live):
                if args.once and not running:
                    break
            time.sleep(0.2)
        stop_capture()
        return 0

    # Steady state: macOS menu bar companion (quiet; no spinning desktop popup).
    # Headless / --once / --inject keep the wait loop below (or already returned).
    if (
        sys.platform == "darwin"
        and not args.headless
        and _can_gui()
    ):
        try:
            from . import menubar

            if menubar.available():
                menubar.run_status_item(
                    stop_event=stop_event,
                    screen_ui=screen_ui,
                    on_quit=on_quit,
                )
                stop_capture()
                _kill_sibling_wowgrok_pids()
                return 0
        except Exception as e:  # noqa: BLE001
            print(f"menubar unavailable ({e}); falling back to wait loop", flush=True)

    while not stop_event.is_set():
        if screen_ui.get("pending"):
            screen_ui["pending"] = False
            try:
                screen_ui["result"] = _notify_mac_screen_recording(
                    str(screen_ui.get("msg") or "")
                )
            except Exception:
                screen_ui["result"] = "continue"
            if screen_ui.get("result") == "quit":
                stop_event.set()
                stop_capture()
            screen_ui["event"].set()
        time.sleep(0.2)
    stop_capture()
    _kill_sibling_wowgrok_pids()
    return 0


def _save(path: Path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")


def _can_gui() -> bool:
    if sys.platform == "darwin" or sys.platform == "win32":
        return True
    return bool(os.environ.get("DISPLAY") or os.environ.get("WAYLAND_DISPLAY"))


if __name__ == "__main__":
    raise SystemExit(main())
