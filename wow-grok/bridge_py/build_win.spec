# -*- mode: python ; coding: utf-8 -*-
# From repo root on Windows Helper / OMEN / GHA windows-latest:
#   pyinstaller --noconfirm bridge_py\build_win.spec
# Output: dist\WoWGrok.exe (tray companion; no console)

from pathlib import Path
from PyInstaller.utils.hooks import collect_data_files, collect_submodules

SPECDIR = Path(SPECPATH).resolve()
ROOT = SPECDIR.parent

block_cipher = None

a = Analysis(
    [str(SPECDIR / 'run_entry.py')],
    pathex=[str(ROOT)],
    binaries=[],
    datas=[
        (str(SPECDIR / 'config.example.json'), 'bridge_py'),
        (str(SPECDIR / 'capture.ps1'), 'bridge'),
        (str(ROOT / 'addon' / 'WoWGrok'), 'addon/WoWGrok'),
    ] + collect_data_files('certifi'),
    hiddenimports=[
        'bridge_py',
        'bridge_py.__main__',
        'bridge_py.bridge',
        'bridge_py.capture_mac',
        'bridge_py.capture_win',
        'bridge_py.config',
        'bridge_py.first_run',
        'bridge_py.install_addon',
        'bridge_py.install_slots',
        'bridge_py.protocol',
        'bridge_py.setup_detect',
        'bridge_py.strip_codec',
        'bridge_py.supervisor',
        'bridge_py.tk_util',
        'bridge_py.xai',
        'bridge_py.ssl_certs',
        'bridge_py.menubar',
        'bridge_py.tray_win',
        'certifi',
        'PIL',
        'pystray',
        'pystray._win32',
        'tkinter',
        '_tkinter',
    ] + collect_submodules('bridge_py') + collect_submodules('pystray'),
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    win_no_prefer_redirects=False,
    win_private_assemblies=False,
    cipher=block_cipher,
    noarchive=False,
)
pyz = PYZ(a.pure, a.zipped_data, cipher=block_cipher)

exe = EXE(
    pyz,
    a.scripts,
    a.binaries,
    a.zipfiles,
    a.datas,
    [],
    name='WoWGrok',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    upx_exclude=[],
    runtime_tmpdir=None,
    console=False,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
)
