"""Mac: offer "Move to Applications" when WoWGrok runs from the installer DMG (0.1.35).

Running the app straight from the mounted disk image (or from macOS App
Translocation) leaves the old copy in /Applications and makes Screen Recording
ask again. On startup (before the bridge, capture or onboarding) we offer to
move the new bundle into Applications. Nothing is ever deleted: an existing
/Applications/WoWGrok.app is moved to ~/Documents/WoWGrok-Mac/WoWGrok-<ver>.app.
Windows / Linux: no-op.
"""
from __future__ import annotations

import os
import plistlib
import signal
import subprocess
import sys
import time
from pathlib import Path
from typing import Callable

APP_NAME = "WoWGrok.app"
TITLE = "Move WoWGrok to Applications?"
BODY = (
    "WoWGrok is running from the installer disk. Move it to Applications so "
    "updates and Screen Recording permission stick?"
)

Run = Callable[..., subprocess.CompletedProcess]


class MoveError(Exception):
    pass


def bundle_path(executable: str | None = None) -> Path | None:
    """``…/WoWGrok.app`` that contains the running executable, if any."""
    p = Path(executable or sys.executable).resolve()
    for parent in [p, *p.parents]:
        if parent.suffix == ".app":
            return parent
    return None


def _is_ro_mount(path: Path) -> bool:
    try:
        return bool(os.statvfs(str(path)).f_flag & getattr(os, "ST_RDONLY", 1))
    except OSError:
        return False


def _hdiutil_mounts(run: Run = subprocess.run) -> list[str]:
    """Mount points of attached disk images (``hdiutil info``)."""
    try:
        out = run(["/usr/bin/hdiutil", "info"], capture_output=True, text=True, timeout=15).stdout
    except Exception:
        return []
    mounts = []
    for line in (out or "").splitlines():
        parts = line.split("\t")
        last = parts[-1].strip() if parts else ""
        if last.startswith("/Volumes/"):
            mounts.append(last)
    return mounts


def needs_move(
    app: Path | str | None,
    *,
    home: Path | None = None,
    is_ro: Callable[[Path], bool] = _is_ro_mount,
    image_mounts: Callable[[], list[str]] = lambda: [],
) -> bool:
    """True when the bundle runs from a DMG / read-only volume / translocation."""
    if not app:
        return False
    s = str(app)
    home = home or Path.home()
    if "/AppTranslocation/" in s:
        return True
    for ok in ("/Applications/", str(home / "Applications") + "/"):
        if s.startswith(ok):
            return False
    if s.startswith("/Volumes/"):
        return True
    if any(s == m or s.startswith(m.rstrip("/") + "/") for m in image_mounts()):
        return True
    return is_ro(Path(s))


def bundle_version(app: Path) -> str:
    try:
        with open(Path(app) / "Contents" / "Info.plist", "rb") as f:
            return str(plistlib.load(f).get("CFBundleShortVersionString") or "unknown")
    except Exception:
        return "unknown"


def backup_name(backup_dir: Path, version: str, *, now: float | None = None) -> Path:
    """``WoWGrok-<ver>.app``, or with a timestamp suffix when taken."""
    base = Path(backup_dir) / f"WoWGrok-{version}.app"
    if not base.exists():
        return base
    stamp = time.strftime("%Y%m%d-%H%M%S", time.localtime(now))
    cand = Path(backup_dir) / f"WoWGrok-{version}-{stamp}.app"
    n = 1
    while cand.exists():
        n += 1
        cand = Path(backup_dir) / f"WoWGrok-{version}-{stamp}-{n}.app"
    return cand


def target_dir(home: Path | None = None) -> tuple[Path, bool]:
    """(/Applications, False) when writable, else (~/Applications, True)."""
    apps = Path("/Applications")
    if apps.is_dir() and os.access(apps, os.W_OK):
        return apps, False
    return (home or Path.home()) / "Applications", True


def quit_other_instances(
    dest_app: Path,
    *,
    run: Run = subprocess.run,
    kill: Callable[[int, int], None] = os.kill,
    sleep: Callable[[float], None] = time.sleep,
    timeout: float = 10.0,
) -> list[int]:
    """SIGTERM WoWGrok processes running from ``dest_app``; wait up to ``timeout``."""
    pattern = str(dest_app) + "/Contents/"
    try:
        out = run(["/usr/bin/pgrep", "-f", pattern], capture_output=True, text=True).stdout
    except Exception:
        return []
    me = os.getpid()
    pids = [int(x) for x in (out or "").split() if x.isdigit() and int(x) != me]
    for pid in pids:
        try:
            kill(pid, signal.SIGTERM)
        except OSError:
            pass
    waited = 0.0
    alive = list(pids)
    while alive and waited < timeout:
        sleep(0.25)
        waited += 0.25
        still = []
        for pid in alive:
            try:
                kill(pid, 0)
                still.append(pid)
            except OSError:
                pass
        alive = still
    return pids


def volume_root(app: Path) -> Path | None:
    parts = Path(app).parts
    if len(parts) >= 3 and parts[1] == "Volumes":
        return Path("/", parts[1], parts[2])
    return None


def move_to_applications(
    src_app: Path,
    *,
    home: Path | None = None,
    dest_dir: Path | None = None,
    run: Run = subprocess.run,
    kill: Callable[[int, int], None] = os.kill,
    sleep: Callable[[float], None] = time.sleep,
    log: Callable[[str], None] = print,
) -> tuple[Path, bool]:
    """Install ``src_app`` into Applications. Returns (installed path, used ~/Applications).

    Raises :class:`MoveError` on failure (nothing deleted; old app stays in backup).
    """
    home = home or Path.home()
    fallback = False
    if dest_dir is None:
        dest_dir, fallback = target_dir(home)
    dest_dir.mkdir(parents=True, exist_ok=True)
    dest = dest_dir / APP_NAME
    new_ver = bundle_version(src_app)

    quit_other_instances(dest, run=run, kill=kill, sleep=sleep)

    if dest.exists():
        bdir = home / "Documents" / "WoWGrok-Mac"
        bdir.mkdir(parents=True, exist_ok=True)
        backup = backup_name(bdir, bundle_version(dest))
        try:
            os.rename(dest, backup)
        except OSError as e:
            raise MoveError(f"Could not move the old {dest} to {backup}: {e}") from e
        log(f"move-to-apps: old app moved to {backup}")

    r = run(["/usr/bin/ditto", str(src_app), str(dest)], capture_output=True, text=True)
    if r.returncode != 0:
        raise MoveError(f"ditto failed: {(r.stderr or '').strip() or r.returncode}")
    r = run(
        ["/usr/bin/codesign", "--verify", "--deep", "--strict", str(dest)],
        capture_output=True,
        text=True,
    )
    if r.returncode != 0:
        raise MoveError(f"codesign check failed: {(r.stderr or '').strip() or r.returncode}")
    got = bundle_version(dest)
    if got != new_ver:
        raise MoveError(f"version mismatch after copy: {got} != {new_ver}")
    log(f"move-to-apps: installed {new_ver} at {dest}")
    return dest, fallback


def offer_if_needed(
    *,
    ask: Callable[[str, str], bool] | None = None,
    info: Callable[[str, str], None] | None = None,
    run: Run = subprocess.run,
    log: Callable[[str], None] = print,
) -> bool:
    """Mac startup hook. Returns True when this instance should exit (moved + relaunched)."""
    if sys.platform != "darwin" or not getattr(sys, "frozen", False):
        return False
    app = bundle_path()
    if not needs_move(app, image_mounts=lambda: _hdiutil_mounts(run)):
        return False
    if ask is None or info is None:
        from . import tk_util

        ask = ask or (lambda t, b: tk_util.ask_choice_dialog(
            t, b, yes="Move to Applications", no="Not now"))
        info = info or tk_util.show_info_dialog
    try:
        if not ask(TITLE, BODY):
            log("move-to-apps: Not now")
            return False
    except Exception as e:  # no GUI -> keep running as before
        log(f"move-to-apps: dialog failed: {e}")
        return False
    try:
        dest, fallback = move_to_applications(app, run=run, log=log)
    except Exception as e:
        log(f"move-to-apps: failed: {e}")
        try:
            info("WoWGrok", f"Could not move WoWGrok to Applications:\n\n{e}\n\n"
                 "WoWGrok will keep running from the installer disk.")
        except Exception:
            pass
        return False
    if fallback:
        try:
            info("WoWGrok", f"/Applications is not writable, so WoWGrok was installed in\n{dest.parent}.")
        except Exception:
            pass
    run(["/usr/bin/open", "-n", str(dest)])
    vol = volume_root(app)
    if vol is not None:
        # Best effort; usually busy until this process exits, so detach in background.
        try:
            subprocess.Popen(
                ["/bin/sh", "-c", f'sleep 3; /usr/bin/hdiutil detach "$0" >/dev/null 2>&1', str(vol)],
                start_new_session=True,
            )
        except Exception:
            pass
    return True
