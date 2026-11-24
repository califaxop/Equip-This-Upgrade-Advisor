#!/usr/bin/env python3
"""Build Guides.lua: each spec's guide from Forever Upgrades (https://foreverupgrades.com):
  - stat weights (its "Stat Weights": Equip This!'s spec presets),
  - the rotation (its priority list, in order; shown by /eqt guide),
  - for damage specs, the rotation played out (its "Sim DPS" breakdown) at levels 30, 50 and 60:
    each ability's share of the damage and casts a minute (items that improve a skill count by it).

    python3 tools/guides/build.py [out=Guides.lua]
"""
import json, subprocess, sys, time, datetime

SITE = "https://foreverupgrades.com"
# Forever Upgrades spec id -> Equip This! spec key (class:talent tree)
SPECS = {
    161: "WARRIOR:1", 164: "WARRIOR:2", 163: "WARRIOR:3",
    382: "PALADIN:1", 383: "PALADIN:2", 381: "PALADIN:3",
    361: "HUNTER:1", 363: "HUNTER:2", 362: "HUNTER:3",
    182: "ROGUE:1", 181: "ROGUE:2", 183: "ROGUE:3",
    201: "PRIEST:1", 202: "PRIEST:2", 203: "PRIEST:3",
    261: "SHAMAN:1", 263: "SHAMAN:2", 262: "SHAMAN:3",
    81: "MAGE:1", 41: "MAGE:2", 61: "MAGE:3",
    302: "WARLOCK:1", 303: "WARLOCK:2", 301: "WARLOCK:3",
    283: "DRUID:1", 281: "DRUID:2", 282: "DRUID:3",
}
DAMAGE_ROLES = {"melee", "caster", "ranged"}  # (tanks: the site sims damage taken; healers: healing)
LEVELS = (("30", ""), ("50", ""), ("60", "dungeon"))
# the game's damage meter names
RENAME = {"melee": "Attack", "windfury": "Windfury Weapon"}
# "Lightning Bolt (Maelstrom)" is a cast of its own; "(Overload)", "(DoT)", "(off hand)" add damage only
CAST_SUFFIX = {"maelstrom"}
# site weight -> Equip This! stat, and the factor to its unit (ratings per 1% at level 60: hit 10,
# crit 14, haste 10, dodge 12, parry 15, block 5; wowsims/forever, foreverdb.net)
def stat_map(role):
    spell = role in ("caster", "healer")
    return {
        "str": ("STR", 1), "agi": ("AGI", 1), "sta": ("STA", 1), "int": ("INT", 1), "spi": ("SPI", 1),
        "ap": ("AP", 1), "rap": ("RAP", 1), "sp": ("SP", 1), "heal": ("HEAL", 1), "mp5": ("MP5", 1),
        "wdps": ("DPS", 1), "armor": ("ARMOR", 1), "bonus_armor": ("ARMOR", 1), "block_value": ("BLOCKVALUE", 1),
        "defense": ("DEF", 1), "dodge": ("DODGE", 12), "parry": ("PARRY", 15), "block": ("BLOCK", 5),
        "hit": ("SPELLHIT" if spell else "HIT", 10), "crit": ("SPELLCRIT" if spell else "CRIT", 14),
        "haste": ("HASTE", 10),
    }


def curl(url):
    r = subprocess.run(["curl", "-sS", "-f", "-m", "300", url], capture_output=True)
    if r.returncode != 0:
        raise RuntimeError(f"{url}: {r.stderr.decode(errors='replace').strip()}")
    return r.stdout


def site(path):
    time.sleep(0.3)
    return json.loads(curl(SITE + path))


def split(breakdown):
    parts, order = {}, []
    for b in breakdown or []:
        name, share, casts = b["ability"].strip(), float(b.get("share") or 0), float(b.get("casts") or 0)
        if share <= 0:
            continue
        base, suffix = name, None
        if name.endswith(")") and " (" in name:
            base, suffix = name[:-1].split(" (", 1)
            suffix = suffix.lower()
        base = RENAME.get(base.lower(), base)
        key = base.lower()
        if key not in parts:
            parts[key] = [base, 0.0, 0.0]
            order.append(key)
        parts[key][1] += share
        if suffix is None or suffix in CAST_SUFFIX:
            parts[key][2] += casts
    total = sum(p[1] for p in parts.values()) or 1
    out = [[p[0], p[1] / total, p[2]] for p in (parts[k] for k in order)]
    out.sort(key=lambda p: -p[1])
    return out


def lua(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def num(x):
    return ("%.3f" % x).rstrip("0").rstrip(".") if x != int(x) else str(int(x))


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "Guides.lua"
    blocks = []
    for sid, key in SPECS.items():
        g = site(f"/api/class-guide/{sid}")
        role = g.get("role")
        smap = stat_map(role)
        weights = {}
        for w in g.get("weights") or []:
            m = smap.get(w["key"])
            if m and w.get("value"):
                weights[m[0]] = max(weights.get(m[0], 0), float(w["value"]) * m[1])
        rot = [r["ability"] for r in g.get("rotation") or []]
        lines = [f'  ["{key}"] = {{ -- {g["spec"]} {g["class"]}']
        lines.append("    weights = { " + ", ".join(f"{k} = {num(v)}" for k, v in sorted(weights.items())) + " },")
        lines.append("    rotation = { " + ", ".join(lua(r) for r in rot) + " },")
        if role in DAMAGE_ROLES:
            levels = []
            for lvl, gear in LEVELS:
                d = site(f"/api/rank-sim/{sid}?level={lvl}" + (f"&gear={gear}" if gear else ""))
                fight = float((d.get("options") or {}).get("fight_seconds") or 60)
                parts = split((d.get("sim") or {}).get("breakdown"))
                cells = ["{ %s, %.3f, %.1f }" % (lua(n), sh, c * 60 / fight) for n, sh, c in parts]
                if cells:
                    levels.append(f"      [{lvl}] = {{ {', '.join(cells)} }},")
            if levels:
                lines.append("    levels = {")
                lines += levels
                lines.append("    },")
        lines.append("  },")
        blocks += lines
    stamp = datetime.date.today().isoformat()
    with open(out, "w", newline="\n") as f:
        f.write("-- Generated by tools/guides/build.py: each spec's guide from Forever Upgrades (foreverupgrades.com).\n")
        f.write("-- Per spec: stat weights (points per unit), the rotation in priority order, and (damage specs) the\n")
        f.write("-- rotation played out at levels 30, 50 and 60: { ability, share of damage, casts a minute }.\n")
        f.write("local _, ns = ...\n")
        f.write(f'ns.GUIDE = {{ build = "{stamp}", source = "Forever Upgrades",\n')
        f.write("\n".join(blocks) + "\n}\n")
    print(f"wrote {out}")


if __name__ == "__main__":
    main()
