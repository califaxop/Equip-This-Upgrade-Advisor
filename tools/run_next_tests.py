"""Runs EquipThisNext's offline tests (EquipThisNext/Tests/run.lua) in a Lua 5.1 runtime, the
Lua version the game uses. Needs the lupa package (pip install lupa). Or, with a Lua 5.1
interpreter:  cd EquipThisNext && lua5.1 Tests/run.lua"""
import os
import sys
from lupa.lua51 import LuaRuntime

root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "EquipThisNext")
os.chdir(root)
L = LuaRuntime()
L.execute('ROOT = "./"; os.exit = function(code) EXIT = code end')
if len(sys.argv) > 1 and sys.argv[1] == "bench":
    L.execute('BENCH = true')
L.execute(open("Tests/run.lua").read())
sys.exit(1 if L.eval("EXIT") else 0)
