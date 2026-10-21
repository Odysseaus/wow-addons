"""Find WoW/Forever Interface/AddOns paths (Mac + Windows). Ported from setup.js."""
from __future__ import annotations

import os
import sys
from pathlib import Path

# Order matters: detection lists, the WoW-root coercion in
# :func:`coerce_client` and the wizard's default selection all follow it.
# ``_forever_`` (WoW Forever) is first since 0.1.32.
FLAVORS = (
    "_forever_",
    "_classic_beta_",
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
    """Map a picked folder to a WoW client (flavor) root.

    A bare ``World of Warcraft`` root with several flavors resolves to the
    first flavor in :data:`FLAVORS` order (``_forever_`` first). Callers that
    must not guess should check :func:`flavor_clients_under` first.
    """
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


def flavor_clients_under(root: str | Path) -> list[Path]:
    """Flavor folders (``_forever_`` …) with an Interface/AddOns under ``root``.

    In :data:`FLAVORS` order. Empty when ``root`` is not a WoW root.
    """
    base = Path(root).expanduser()
    out: list[Path] = []
    for flavor in FLAVORS:
        if (base / flavor / "Interface" / "AddOns").is_dir():
            out.append((base / flavor).resolve())
    return out


def flavor_of(addons_dir: str | Path) -> str:
    """Flavor folder name for an ``…/<flavor>/Interface/AddOns`` path (``""`` if unknown)."""
    p = Path(str(addons_dir))
    if p.name.lower() == "addons" and p.parent.name.lower() == "interface":
        return p.parent.parent.name
    return ""


def client_root_for_addons(addons_dir: str | Path) -> Path:
    """``…/<flavor>/Interface/AddOns`` → ``…/<flavor>`` (the client / flavor root)."""
    return Path(str(addons_dir)).parent.parent


FLAVOR_LABELS = {
    "_forever_": "WoW Forever",
    "_classic_beta_": "Classic beta",
    "_retail_": "Retail",
    "_classic_era_": "Classic Era",
    "_classic_": "Classic",
}


def flavor_label(addons_dir: str | Path) -> str:
    """Human label for a wizard choice, e.g. ``WoW Forever (_forever_)``."""
    flavor = flavor_of(addons_dir)
    if not flavor:
        return Path(str(addons_dir)).name or str(addons_dir)
    nice = FLAVOR_LABELS.get(flavor)
    return f"{nice} ({flavor})" if nice else flavor


def sort_by_flavor(paths: list[Path]) -> list[Path]:
    """Stable sort: known flavors in :data:`FLAVORS` order, unknown last."""
    order = {f: i for i, f in enumerate(FLAVORS)}
    return sorted(paths, key=lambda p: order.get(flavor_of(p), len(FLAVORS)))


def preferred_addons_dir(candidates: list[Path] | list[str]) -> Path | None:
    """Default wizard selection: ``_forever_`` when present, else the first by flavor order."""
    paths = [Path(str(c)) for c in candidates or []]
    if not paths:
        return None
    return sort_by_flavor(paths)[0]


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
    seen: set[str] = set()
    for c in addon_candidates(platform):
        p = Path(c)
        if p.is_dir():
            r = p.resolve()
            k = str(r).lower()
            if k in seen:
                continue
            seen.add(k)
            found.append(r)
    return found


def normalize_addons_selection(path: str | Path) -> Path | None:
    """Accept AddOns folder or WoW client/flavor root; return AddOns Path.

    A bare ``World of Warcraft`` root resolves to the first flavor in
    :data:`FLAVORS` (``_forever_`` first since 0.1.32 — it used to be
    ``_classic_beta_``, so picking the root silently kept classic beta).
    """
    p = Path(path).expanduser().resolve()
    if p.name.lower() == "addons" and p.parent.name.lower() == "interface":
        return p
    # Picked a folder *inside* AddOns (e.g. …/AddOns/WoWGrok): use its AddOns.
    if p.parent.name.lower() == "addons" and p.parent.parent.name.lower() == "interface":
        return p.parent
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
