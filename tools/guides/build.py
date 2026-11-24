#!/usr/bin/env python3
"""Build Guides.lua: each spec's guide from Forever Upgrades (https://foreverupgrades.com):
  - stat weights (its "Stat Weights": Equip This!'s spec presets),
  - the rotation (its priority list, in order; shown by /eqt guide),
  - for damage specs, the rotation played out (its "Sim DPS" breakdown) at levels 30, 50 and 60:
    each ability's share of the damage and casts a minute (items that improve a skill count by it).

    python3 tools/guides/build.py [out=Guides.lua] [Forever build]

Also writes Spells.lua next to it: every rank of the spells in those rotations from Forever's own spell
tables (wago.tools), so the addon works out each ability's damage or healing from current data.
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
DAMAGE_ROLES = {"melee", "caster", "ranged", "healer"}  # (tanks: the site sims damage taken)
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
        "haste": ("HASTE", 10), "expertise": ("EXPERTISE", 10), "spell_pen": ("SPELLPEN", 1),
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


# ---------------------------------------------------------------------------------------------
# Spells.lua: every rank of the spells in the rotations, from Forever's own spell tables
# (wago.tools, product wowf), refreshed each week so patches are picked up:
#   [spell ID] = { name, base level, max level, school mask, cast ms, cooldown ms, duration ms,
#                  { { effect, aura, base points, points per level, spell power coef., attack power coef.,
#                      tick ms, points per combo point }, ... } }
# Effects kept: 2 school damage, 10 heal, 31 weapon %, 121 / 58 / 17 weapon damage + flat bonus,
# 6 apply aura / 27 area on the ground (Consecration) with 3 periodic damage, 8 periodic heal, 69 absorb.
# ---------------------------------------------------------------------------------------------
import csv, io, collections
WAGO = "https://wago.tools/db2/{}/csv?build={}"
KEEP_EFFECTS = {"2", "10", "31", "121", "58", "17"}
KEEP_AURAS = {"3", "8", "69"}


def table(name, build):
    return list(csv.DictReader(io.StringIO(curl(WAGO.format(name, build)).decode("utf-8"))))


def latest_build():
    return json.loads(curl("https://wago.tools/api/builds"))["wowf"][0]["version"]


def fnum(x, default=0.0):
    try:
        return float(x)
    except (TypeError, ValueError):
        return default


def fmt(x):
    x = round(float(x), 4)
    return str(int(x)) if x == int(x) else repr(x)


def build_spells(names, out, build=None):
    build = build or latest_build()
    wanted = set()
    for n in names:
        base = n.split(" (")[0].strip()
        if base and base.lower() not in ("attack", "melee", "auto shot"):
            wanted.add(base.lower())
    player = {r["Spell"] for r in table("SkillLineAbility", build)}
    ids = collections.defaultdict(list)
    for r in table("SpellName", build):
        if r["ID"] in player and r["Name_lang"].lower() in wanted:
            ids[r["Name_lang"]].append(r["ID"])
    allids = {i for v in ids.values() for i in v}
    levels = {r["SpellID"]: r for r in table("SpellLevels", build) if r["SpellID"] in allids and r["DifficultyID"] == "0"}
    misc = {r["SpellID"]: r for r in table("SpellMisc", build) if r["SpellID"] in allids and r["DifficultyID"] == "0"}
    casts = {r["ID"]: int(fnum(r["Base"])) for r in table("SpellCastTimes", build)}
    durs = {r["ID"]: int(fnum(r["Duration"])) for r in table("SpellDuration", build)}
    cds = {r["SpellID"]: max(int(fnum(r["RecoveryTime"])), int(fnum(r["CategoryRecoveryTime"])))
           for r in table("SpellCooldowns", build) if r["SpellID"] in allids}
    effects = collections.defaultdict(list)
    for r in table("SpellEffect", build):
        if r["SpellID"] in allids and r["DifficultyID"] == "0" and (
                r["Effect"] in KEEP_EFFECTS or (r["Effect"] in ("6", "27") and r["EffectAura"] in KEEP_AURAS)):
            effects[r["SpellID"]].append(r)
    # weapon imbues (Windfury Weapon...): the enchant on the weapon -> the rank that puts it there
    imbues = {}
    for r in table("SpellEffect", build):
        if r["SpellID"] in allids and r["Effect"] in ("54", "360") and fnum(r["EffectMiscValue_0"]) > 0:
            imbues[int(fnum(r["EffectMiscValue_0"]))] = int(r["SpellID"])
    lines, kept = [], 0
    for name in sorted(ids):
        for i in sorted(ids[name], key=int):
            effs = sorted(effects.get(i, []), key=lambda r: int(r["EffectIndex"]))
            if not effs:
                continue
            lv, m = levels.get(i, {}), misc.get(i, {})
            cells = []
            for r in effs:
                cells.append("{ %s }" % ", ".join(fmt(v) for v in (
                    r["Effect"], r["EffectAura"], fnum(r["EffectBasePointsF"]), fnum(r["EffectRealPointsPerLevel"]),
                    fnum(r["EffectBonusCoefficient"]), fnum(r["BonusCoefficientFromAP"]), fnum(r["EffectAuraPeriod"]),
                    fnum(r["EffectPointsPerResource"]))))
            lines.append("  [%s] = { %s, %s, %s, %s, %s, %s, %s, { %s } }," % (
                i, lua(name), int(fnum(lv.get("BaseLevel"))), int(fnum(lv.get("MaxLevel"))), int(fnum(m.get("SchoolMask"))),
                casts.get(m.get("CastingTimeIndex"), 0), cds.get(i, 0), durs.get(m.get("DurationIndex"), 0), ", ".join(cells)))
            kept += 1
    with open(out, "w", newline="\n") as f:
        f.write("-- Generated by tools/guides/build.py from Forever's own spell tables (wago.tools, product wowf).\n")
        f.write("-- Every rank of the spells in the rotations: [spell ID] = { name, base level, max level, school mask,\n")
        f.write("-- cast ms, cooldown ms, duration ms, { { effect, aura, base points, points per level, spell power\n")
        f.write("-- coefficient, attack power coefficient, tick ms, points per combo point }, ... } }\n")
        f.write("local _, ns = ...\n")
        f.write(f'ns.SPELL_DATA_BUILD = "{build}"\n')
        f.write("ns.SPELLS = {\n" + "\n".join(lines) + "\n}\n")
        f.write("-- weapon imbues: [enchant ID on the weapon] = the spell rank that applies it\n")
        f.write("ns.IMBUES = { " + ", ".join(f"[{k}] = {v}" for k, v in sorted(imbues.items())) + " }\n")
    print(f"wrote {out}: {kept} spell ranks of {len(ids)} spells (Forever build {build})")
    missing = sorted(n for n in wanted if n not in {k.lower() for k in ids})
    if missing:
        print("  not player spells (procs, pets, talents' passives: valued by the site's share):", ", ".join(missing))


def lua(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def num(x):
    return ("%.3f" % x).rstrip("0").rstrip(".") if x != int(x) else str(int(x))


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "Guides.lua"
    blocks, names = [], set()
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
        names.update(rot)
        lines = [f'  ["{key}"] = {{ -- {g["spec"]} {g["class"]}']
        unit = "HPS" if role == "healer" else "DPS"
        lines.append(f'    unit = "{unit}",')
        prio = [p.get("stat", "") for p in g.get("stat_priority") or [] if p.get("stat")]
        lines.append("    priority = { " + ", ".join(lua(p) for p in prio) + " },")
        lines.append("    weights = { " + ", ".join(f"{k} = {num(v)}" for k, v in sorted(weights.items())) + " },")
        lines.append("    rotation = { " + ", ".join(lua(r) for r in rot) + " },")
        if role in DAMAGE_ROLES:
            levels = []
            for lvl, gear in LEVELS:
                d = site(f"/api/rank-sim/{sid}?level={lvl}" + (f"&gear={gear}" if gear else ""))
                fight = float((d.get("options") or {}).get("fight_seconds") or 60)
                parts = split((d.get("sim") or {}).get("breakdown"))
                cells = ["{ %s, %.3f, %.1f }" % (lua(n), sh, c * 60 / fight) for n, sh, c in parts]
                names.update(n for n, _, _ in parts)
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
    spells_out = out.replace("Guides.lua", "Spells.lua") if out.endswith("Guides.lua") else "Spells.lua"
    build_spells(names, spells_out, sys.argv[2] if len(sys.argv) > 2 else None)


if __name__ == "__main__":
    main()
