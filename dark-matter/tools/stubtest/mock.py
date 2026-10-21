"""Run the addon in a stub WoW environment (needs `pip install lupa`).
usage: MODE=full|journal|minimal [DM_RENDER_DIR=out] python mock.py <addon dir>
With MODE=full and DM_RENDER_DIR set it also writes layout-<tab>.json for tools/render_preview.py."""
import os
import sys
from lupa.lua51 import LuaRuntime
L = LuaRuntime()
L.globals().arg = L.table_from({1: sys.argv[1]})
L.execute(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'mock.lua')).read())
