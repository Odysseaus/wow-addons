# -*- mode: python ; coding: utf-8 -*-
# From repo root on a Mac:
#   pyinstaller --noconfirm bridge_py/build_mac.spec
# Output: dist/WoWGrok.app — grant Screen Recording to the .app.

import sys
from pathlib import Path

SPECDIR = Path(SPECPATH).resolve()
ROOT = SPECDIR.parent

block_cipher = None

a = Analysis(
    [str(SPECDIR / 'run_entry.py')],
    pathex=[str(ROOT)],
    binaries=[],
    datas=[
        (str(SPECDIR / 'config.example.json'), 'bridge_py'),
        (str(ROOT / 'addon' / 'WoWGrok'), 'addon/WoWGrok'),
    ],
    hiddenimports=[
        'bridge_py',
        'bridge_py.bridge',
        'bridge_py.capture_mac',
        'bridge_py.strip_codec',
        'bridge_py.config',
        'bridge_py.first_run',
        'bridge_py.protocol',
        'bridge_py.xai',
        'PIL',
    ],
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
    [],
    exclude_binaries=True,
    name='WoWGrok',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    console=False,
    disable_windowed_traceback=False,
    argv_emulation=True,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
)
coll = COLLECT(
    exe,
    a.binaries,
    a.zipfiles,
    a.datas,
    strip=False,
    upx=True,
    upx_exclude=[],
    name='WoWGrok',
)
app = BUNDLE(
    coll,
    name='WoWGrok.app',
    icon=None,
    bundle_identifier='com.wowgrok.bridge',
    info_plist={
        'NSHighResolutionCapable': True,
        'NSAppleEventsUsageDescription':
            'WoWGrok locates the World of Warcraft window for pixel-strip capture.',
    },
)
