"""Bundles the engine (EquipThisNext's source) into Equip This! (EquipThis/Engine/), for 5.0+.

EquipThisNext stays the engine's source and test bed; this copies its files into a sub-namespace
(ns.Engine) of Equip This!, with its own saved data (EquipThisEngineDB) and diagnostics (/eqn), and
writes the file list into EquipThis.toc between the "# Engine" markers.

  python tools/next/bundle.py <EquipThis folder>
"""
import os, re, shutil, sys

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.normpath(os.path.join(HERE, "..", "..", "EquipThisNext"))


def main():
    dst_root = os.path.abspath(sys.argv[1])
    eng = os.path.join(dst_root, "Engine")
    if os.path.isdir(eng):
        shutil.rmtree(eng)
    os.makedirs(eng)
    files = [l.strip() for l in open(os.path.join(SRC, "EquipThisNext.toc")) if l.strip() and not l.startswith("#")]
    out_list = ["Engine\\Init.lua"]
    with open(os.path.join(eng, "Init.lua"), "w", newline="\n") as f:
        f.write("-- The engine's own namespace inside Equip This! (bundled by tools/next/bundle.py from EquipThisNext).\n"
                "local _, ns = ...\nns.Engine = ns.Engine or { bundled = true }\n")
    for rel in files:
        rel_u = rel.replace("\\", "/")
        if rel_u.startswith("UI/Tooltip") is False and False:
            pass
        text = open(os.path.join(SRC, rel_u), encoding="utf-8").read()
        text, n = re.subn(r"^local (ADDON|_), ns = \.\.\.$", r"local \1, ns = ...; ns = ns.Engine", text, count=1, flags=re.M)
        assert n == 1, rel
        text = text.replace("EquipThisNextDB", "EquipThisEngineDB").replace("EQUIPTHISNEXT", "EQUIPTHISENGINE")
        text = text.replace('local PREFIX = "|cff33ff99Equip This! Next|r:"', 'local PREFIX = "|cff7fd6ffEquip This!:|r"')
        text = text.replace('ns.title = "Equip This! Next"', 'ns.title = "Equip This! (engine)"')
        p = os.path.join(eng, rel_u)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, "w", newline="\n", encoding="utf-8") as f:
            f.write("-- (bundled from EquipThisNext: edit it there and run tools/next/bundle.py)\n" + text)
        out_list.append("Engine\\" + rel)
    toc = os.path.join(dst_root, "EquipThis.toc")
    t = open(toc, encoding="utf-8").read()
    block = "# Engine (tools/next/bundle.py)\n" + "\n".join(out_list) + "\n# /Engine\n"
    if "# Engine (tools/next/bundle.py)" in t:
        t = re.sub(r"# Engine \(tools/next/bundle.py\)\n.*?# /Engine\n", block.replace("\\", "\\\\"), t, flags=re.S)
    else:
        t = t.rstrip("\n") + "\n\n" + block
    open(toc, "w", newline="\n", encoding="utf-8").write(t)
    print("bundled %d files into %s" % (len(out_list), eng))


if __name__ == "__main__":
    main()
