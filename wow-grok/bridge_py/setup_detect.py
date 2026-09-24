"""Find WoW/Forever Interface/AddOns paths (Mac + Windows). Ported from setup.js."""
from __future__ import annotations

import os
import sys
from pathlib import Path

FLAVORS = (
    "_classic_beta_",
    "_forever_",
    "_retail_",
    "_classic_era_",
    "_classic_",
)


def candidate_roots(platform: str | None = None) -> list[Path]:
    platform = platform or sys.platform
    home = Path.home()
    if platform == "darwin":
        return [
            home / "Applications" / "World of Warcraft",
            Path("/Applications/World of Warcraft"),
        ]
    roots: list[Path] = []
    for env in ("ProgramFiles(x86)", "ProgramFiles"):
        v = os.environ.get(env)
        if v:
            roots.append(Path(v) / "World of Warcraft")
    for drive in ("D:\\", "E:\\", "C:\\Games", "D:\\Games", "E:\\Games"):
        roots.append(Path(drive) / "World of Warcraft")
    # de-dupe while preserving order
    seen: set[str] = set()
    out: list[Path] = []
    for r in roots:
        k = str(r).lower()
        if k not in seen:
            seen.add(k)
            out.append(r)
    return out


def addon_candidates(platform: str | None = None) -> list[str]:
    """All plausible Interface/AddOns paths under common WoW roots + flavors."""
    paths: list[str] = []
    for root in candidate_roots(platform):
        for flavor in FLAVORS:
            paths.append(str(root / flavor / "Interface" / "AddOns"))
    return paths


def is_client(dir_path: Path, platform: str | None = None) -> bool:
    platform = platform or sys.platform
    try:
        if not (dir_path / "Interface").exists():
            return False
        names = [p.name for p in dir_path.iterdir()]
        if platform == "darwin":
            if any(
                n.lower().startswith("wow") and n.lower().endswith(".app")
                for n in names
            ) or any(
                n.lower().startswith("world of warcraft") and n.lower().endswith(".app")
                for n in names
            ):
                return True
            macos = dir_path / "Contents" / "MacOS"
            if macos.is_dir() and any(f.name.lower().startswith("wow") for f in macos.iterdir()):
                return True
            if (dir_path / "Interface" / "AddOns").exists():
                return True
            return False
        return any(n.lower().startswith("wow") and n.lower().endswith(".exe") for n in names)
    except OSError:
        return False


def coerce_client(dir_path: str | Path, platform: str | None = None) -> Path | None:
    d = Path(dir_path).resolve()
    if is_client(d, platform):
        return d
    if d.suffix.lower() == ".app" and is_client(d.parent, platform):
        return d.parent
    for flavor in FLAVORS:
        nested = d / flavor
        if is_client(nested, platform):
            return nested
    return None


def find_addons_dirs(platform: str | None = None, exist_only: bool = True) -> list[Path]:
    """Return existing (or all candidate) AddOns directories."""
    found: list[Path] = []
    for root in candidate_roots(platform):
        for flavor in FLAVORS:
            client = root / flavor
            addons = client / "Interface" / "AddOns"
            if exist_only:
                if addons.is_dir() or is_client(client, platform):
                    if addons.exists() or True:
                        # Prefer real existing AddOns dirs
                        if addons.is_dir():
                            found.append(addons.resolve())
            else:
                found.append(addons)
    # Also accept AddOns that exist even if is_client is weak
    dedup: list[Path] = []
    seen: set[str] = set()
    for p in found:
        k = str(p).lower()
        if k not in seen:
            seen.add(k)
            dedup.append(p)
    return dedup


def find_existing_addons(platform: str | None = None) -> list[Path]:
    found: list[Path] = []
    for c in addon_candidates(platform):
        p = Path(c)
        if p.is_dir():
            found.append(p.resolve())
    return found


def normalize_addons_selection(path: str | Path) -> Path | None:
    """Accept AddOns folder or WoW client/flavor root; return AddOns Path."""
    p = Path(path).expanduser().resolve()
    if p.name.lower() == "addons" and p.parent.name.lower() == "interface":
        return p
    if (p / "Interface" / "AddOns").is_dir():
        return (p / "Interface" / "AddOns").resolve()
    client = coerce_client(p)
    if client and (client / "Interface" / "AddOns").exists():
        return (client / "Interface" / "AddOns").resolve()
    if (p / "AddOns").is_dir() and p.name.lower() == "interface":
        return (p / "AddOns").resolve()
    return None


def find_accounts(client: Path) -> list[str]:
    base = client / "WTF" / "Account"
    names: list[str] = []
    try:
        for n in base.iterdir():
            if n.name == "SavedVariables":
                continue
            if n.is_dir():
                names.append(n.name)
    except OSError:
        pass
    return sorted(names)


def detect_process_name(client: Path, platform: str | None = None) -> str:
    platform = platform or sys.platform
    try:
        names = [p.name for p in client.iterdir()]
    except OSError:
        return "World of Warcraft" if platform == "darwin" else "WowB"
    if platform == "darwin":
        for pred in (
            lambda n: n.lower() == "wowb.app",
            lambda n: n.lower().startswith("wow") and n.lower().endswith(".app"),
            lambda n: n.lower().startswith("world of warcraft") and n.lower().endswith(".app"),
        ):
            app = next((n for n in names if pred(n)), None)
            if app:
                return app[:-4] if app.lower().endswith(".app") else app
        return "World of Warcraft"
    exe = next((n for n in names if n.lower().startswith("wow") and n.lower().endswith(".exe")), None)
    if exe:
        return exe[:-4]
    return "WowB"
