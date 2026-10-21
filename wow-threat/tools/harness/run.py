import sys, os, lupa
from lupa.lua51 import LuaRuntime
# usage: run.py harness.lua addon_dir  (env MODE / PRESET honoured by the harness)
h, d = os.path.abspath(sys.argv[1]), sys.argv[2]
os.chdir(d)
lua = LuaRuntime(unpack_returned_tuples=True)
pre = os.environ.get("LUAPRE")
if pre: lua.execute(open(pre).read())
lua.execute(open(h).read())
