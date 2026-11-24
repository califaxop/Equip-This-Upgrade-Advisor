#!/usr/bin/env python3
"""Build Guides.lua: each spec's guide from Forever Upgrades (https://foreverupgrades.com):
  - stat weights (its simulator's "Stat Weights": what each stat does for the spec's DPS, HPS or
    effective health), in points per unit of each stat, the main stat at 1,
  - the stat priority (and whether hit has a cap), the rotation, and the role,
  - the talent build its simulator plays (Equip This! scales the stats those talents feed by your own
    ranks), and for tanks the class's damage spec (the damage side of a tank's build),
  - the rotation played out at levels 30, 50 and 60: each ability's share of the output (items that
    improve a skill count by it), and the spec's DPS / HPS / EH at each.

    python3 tools/guides/build.py [out=Guides.lua] [Forever build]

Also writes Enchants.lua next to it: permanent enchants from Forever's own tables (wago.tools), so an
enchanted item counts its enchant ("+5 Strength", Crusader).
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
# Enchants.lua: permanent enchants, from Forever's own tables (wago.tools, product wowf)
# ---------------------------------------------------------------------------------------------
import csv, io, collections
WAGO = "https://wago.tools/db2/{}/csv?build={}"


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


def write_enchants(out, build=None):
    build = build or latest_build()
    enchants = build_enchants(build)
    with open(out, "w", newline="\n") as f:
        f.write("-- Generated by tools/guides/build.py from Forever's own tables (wago.tools, product wowf).\n")
        f.write("-- Permanent enchants: [enchant ID] = { name, false, weapon damage, { stat = amount }, proc = { damage,\n")
        f.write("-- stat, amount, seconds, chance % (0: about once a minute) } }\n")
        f.write("local _, ns = ...\n")
        f.write(f'ns.ENCHANT_DATA_BUILD = "{build}"\n')
        f.write("ns.ENCHANTS = {\n" + "\n".join(enchants) + "\n}\n")
    print(f"wrote {out}: {len(enchants)} enchants (Forever build {build})")


# what an enchant does, from Forever's tables: SpellItemEnchantment's effects (1: a proc spell, 2: weapon
# damage, 3: an equip spell, 5: a stat) and the spells they name (stat auras; a proc's damage or stat buff)
AURA_STAT = {"99": "AP", "124": "RAP", "13": "SP", "135": "HEAL", "57": "SPELLCRIT", "52": "CRIT", "54": "HIT",
             "55": "SPELLHIT", "85": "MP5", "34": "HEALTH"}
MOD_STAT = {"0": "STR", "1": "AGI", "2": "STA", "3": "INT", "4": "SPI"}
ITEM_MOD = {"3": "AGI", "4": "STR", "5": "INT", "6": "SPI", "7": "STA", "45": "SP", "38": "AP", "41": "HEAL"}


def build_enchants(build):
    effects = collections.defaultdict(list)
    for r in table("SpellEffect", build):
        if r["DifficultyID"] == "0":
            effects[r["SpellID"]].append(r)
    misc = {r["SpellID"]: r for r in table("SpellMisc", build) if r["DifficultyID"] == "0"}
    durs = {r["ID"]: int(fnum(r["Duration"])) for r in table("SpellDuration", build)}

    def auras(spell):
        st = {}
        effs = effects.get(spell, [])
        has_sp = any(e["EffectAura"] == "13" for e in effs)
        for e in effs:
            if e["Effect"] != "6":
                continue
            a, bp, mv = e["EffectAura"], fnum(e["EffectBasePointsF"]), e["EffectMiscValue_0"]
            if a == "29":
                for k in (MOD_STAT.values() if mv == "-1" else [MOD_STAT.get(mv)]):
                    if k:
                        st[k] = st.get(k, 0) + bp
            elif a == "22" and mv == "1":
                st["ARMOR"] = st.get("ARMOR", 0) + bp
            elif a in AURA_STAT and not (a == "135" and has_sp):  # (spell damage and healing: spell power)
                k = AURA_STAT[a]
                st[k] = st.get(k, 0) + bp
        return st

    def proc(spell):
        effs = effects.get(spell, [])
        m = misc.get(spell, {})
        dur = durs.get(m.get("DurationIndex"), 0)
        dmg = 0
        for e in effs:
            if e["Effect"] == "2":
                dmg += fnum(e["EffectBasePointsF"])
            elif e["Effect"] == "6" and e["EffectAura"] == "3":
                per = fnum(e["EffectAuraPeriod"])
                dmg += fnum(e["EffectBasePointsF"]) * (max(1, dur // per) if per > 0 and dur > 0 else 1)
        st = auras(spell)
        if dmg > 0:
            return {"damage": dmg}
        if st and dur > 0:
            k, v = next(iter(st.items()))
            return {"stat": k, "amount": v, "seconds": dur / 1000}
        return None

    out = []
    for r in table("SpellItemEnchantment", build):
        name = (r.get("Name_lang") or "").strip()
        if not name:
            continue
        temp = fnum(r.get("Duration")) > 0
        if temp:
            continue  # (imbues, poisons, stones, oils: buffs, not part of an item)
        dmg, stats, pr = 0, {}, None
        for i in range(3):
            eff, pts, arg = r.get(f"Effect_{i}"), fnum(r.get(f"EffectPointsMin_{i}")), r.get(f"EffectArg_{i}")
            if eff == "2":
                dmg += pts
            elif eff == "5":
                k = ITEM_MOD.get(arg)
                if k:
                    stats[k] = stats.get(k, 0) + pts
            elif eff == "3" and arg and arg != "0":
                for k, v in auras(arg).items():
                    stats[k] = stats.get(k, 0) + v
            elif eff == "1" and arg and arg != "0" and not pr:
                pr = proc(arg)
                if pr:
                    pr["chance"] = pts
        if not (dmg or stats or pr):
            continue
        cells = [lua(name), "true" if temp else "false", fmt(dmg),
                 "{ " + ", ".join(f"{k} = {fmt(v)}" for k, v in sorted(stats.items())) + " }"]
        if pr:
            cells.append("{ " + ", ".join(f"{k} = {lua(v) if isinstance(v, str) else fmt(v)}" for k, v in sorted(pr.items())) + " }")
        out.append(f"  [{r['ID']}] = {{ {', '.join(cells)} }},")
    return out


def lua(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def num(x):
    return ("%.3f" % x).rstrip("0").rstrip(".") if x != int(x) else str(int(x))


ID_OF = {v: k for k, v in SPECS.items()}


def talent_build(sid):
    """the talents the site's simulator plays the spec with (level 60): { "Mental Dexterity": 3 }"""
    d = site(f"/api/rank-sim/{sid}?level=60")
    ranks = d.get("talents") or {}
    names = {}
    for tree in d.get("talent_trees") or []:
        for t in tree.get("talents") or []:
            names[t.get("key")] = t.get("name")
    return {names.get(k, k.replace("_", " ").title()): int(v) for k, v in ranks.items() if int(v) > 0}


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
        unit = "HPS" if role == "healer" else ("EH" if role == "tank" else "DPS")
        lines.append(f'    unit = "{unit}", role = "{role}", hitCap = {"true" if g.get("hit_cap") else "false"},')
        if role == "tank":
            # the damage side of a tank's build: the class's damage spec (melee first)
            sib = [x for x in g.get("siblings") or [] if x.get("role") in ("melee", "ranged", "caster")]
            sib.sort(key=lambda x: x.get("role") != "melee")
            if sib and sib[0]["id"] in SPECS:
                lines.append(f'    damageSpec = "{SPECS[sib[0]["id"]]}",')
        prio = [p.get("stat", "") for p in g.get("stat_priority") or [] if p.get("stat")]
        lines.append("    priority = { " + ", ".join(lua(p) for p in prio) + " },")
        lines.append("    weights = { " + ", ".join(f"{k} = {num(v)}" for k, v in sorted(weights.items())) + " },")
        lines.append("    rotation = { " + ", ".join(lua(r) for r in rot) + " },")
        tb = talent_build(sid)
        lines.append("    talents = { " + ", ".join(f"[{lua(n)}] = {r}" for n, r in sorted(tb.items())) + " },")
        out_by = {k: float(v.get("value") or 0) for k, v in (g.get("dps") or {}).items() if isinstance(v, dict)}
        cells = [f"[{k}] = {num(out_by[str(k)])}" for k in (30, 50) if str(k) in out_by]
        top = out_by.get("60-dungeon") or out_by.get("60")
        if top:
            cells.append(f"[60] = {num(top)}")
        lines.append("    output = { " + ", ".join(cells) + " },")
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
        f.write("-- Per spec: what its simulator measures (unit: DPS, HPS or EH), stat weights (points per unit, the main\n")
        f.write("-- stat at 1), the stat priority, the rotation, the talent build it plays, its output at levels 30 / 50 /\n")
        f.write("-- 60, and (damage and healing specs) the rotation played out: { ability, share of output, casts a minute }.\n")
        f.write("local _, ns = ...\n")
        f.write(f'ns.GUIDE = {{ build = "{stamp}", source = "Forever Upgrades",\n')
        f.write("\n".join(blocks) + "\n}\n")
    print(f"wrote {out}")
    enchants_out = out.replace("Guides.lua", "Enchants.lua") if out.endswith("Guides.lua") else "Enchants.lua"
    write_enchants(enchants_out, sys.argv[2] if len(sys.argv) > 2 else None)


if __name__ == "__main__":
    main()
