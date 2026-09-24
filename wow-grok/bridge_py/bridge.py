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
from . import xai

HERE = Path(__file__).resolve().parent
REPO = HERE.parent


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

    def resolve_cwd(raw: str | None) -> str:
        return P.resolve_cwd(raw, default_cwd)

    def slot_file(global_name: str, records: list) -> str:
        return P.lua_table(
            global_name, records, {"cwd": default_cwd, "restore": pending_restore}
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
        if not (Path(cfg["addonDir"]) / "WoWGrok" / "presence").exists():
            return
        state["presence"] = ((state.get("presence") or 0) % presence_max) + 1
        k = state["presence"]
        try:
            atomic_write(
                Path(cfg["addonDir"]) / "WoWGrok" / "presence" / f"{str(k).zfill(4)}.wav",
                P.SILENT_WAV,
            )
        except OSError:
            pass
        for j in range(1, 51):
            n = ((k - 1 + j) % presence_max) + 1
            try:
                atomic_write(
                    Path(cfg["addonDir"])
                    / "WoWGrok"
                    / "presence"
                    / f"{str(n).zfill(4)}.wav",
                    b"",
                )
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

                result = xai.chat(
                    api_key=api_key,
                    model=cfg.get("model"),
                    api_base=cfg.get("apiBase"),
                    input=job.get("text") or "",
                    previous_response_id=prev_id,
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

    def submit(job: dict) -> None:
        if P.already_handled(state, job):
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

    def start_capture() -> None:
        if not cap.get("enabled"):
            return
        if sys.platform == "darwin":
            cmd = [
                sys.executable,
                "-m",
                "bridge_py.capture_mac",
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
        elif sys.platform == "win32":
            cmd = [
                sys.executable,
                "-m",
                "bridge_py.capture_win",
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
                    capture_proc[0] = None
                    if stop_event.is_set():
                        break
                    log(f"capture exited ({proc.returncode}); restarting in 5 s")
                    time.sleep(5)
                except Exception as e:  # noqa: BLE001
                    log("capture spawn error:", e)
                    time.sleep(5)

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
    print(
        f"  capture  : {'on (' + cap_proc + ', ' + str(cap['processName']) + ', '
        + str(cap['cellsPerRow']) + 'x' + str(cap['maxRows']) + ' cells of '
        + str(cap['cellPx']) + 'px)' if cap.get('enabled') else 'off'}"
    )
    print(f"  slots    : {slots}  parallel={max_parallel}")
    if not addon_installed():
        print("  WARNING  : WoWGrok.toc not found under addonDir — copy addon then restart WoW")
    elif not slots_installed():
        print("  WARNING  : slots missing — run: python -m bridge_py.install_slots")

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

    def on_sig(*_a: object) -> None:
        stop_event.set()
        p = capture_proc[0]
        if p and p.poll() is None:
            p.terminate()

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
        return 0

    while not stop_event.is_set():
        time.sleep(0.5)
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
