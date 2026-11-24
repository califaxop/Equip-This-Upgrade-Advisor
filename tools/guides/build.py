#!/usr/bin/env python3
"""Build Guides.lua: each spec's guide from Forever Upgrades (https://foreverupgrades.com), checked
against Forever's own spell tables (wago.tools, product wowf).

From the site, per spec:
  - stat weights (its "Stat Weights", made Equip This! presets),
  - the rotation (its priority list, in order),
  - for damage specs, the rotation played out (its "Sim DPS" breakdown) at levels 30, 50 and 60:
    each ability's share of the damage and casts a minute.
From Forever's tables: each ability's cooldown. The site's numbers can trail Forever's patches
(Stormstrike: 6 s / 150% there, 8 s / 100% in the game), so in game Equip This! reads each ability's
damage from its live tooltip, and caps casts a minute by its cooldown (the live one, else this one).
The report printed lists every ability whose casts the cooldown caps, and Forever's weapon damage %.

    python3 tools/guides/build.py [out=Guides.lua] [forever build]
"""
import csv, io, json, subprocess, sys, time, datetime, collections

SITE = "https://foreverupgrades.com"
WAGO = "https://wago.tools/db2/{}/csv?build={}"
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
# site weight -> Equip This! stat, and the factor to its unit (ratings: 10 per 1%)
def stat_map(role):
    spell = role in ("caster", "healer")
    return {
        "str": ("STR", 1), "agi": ("AGI", 1), "sta": ("STA", 1), "int": ("INT", 1), "spi": ("SPI", 1),
        "ap": ("AP", 1), "rap": ("RAP", 1), "sp": ("SP", 1), "heal": ("HEAL", 1), "mp5": ("MP5", 1),
        "wdps": ("DPS", 1), "armor": ("ARMOR", 1), "bonus_armor": ("ARMOR", 1), "block_value": ("BLOCKVALUE", 1),
        "defense": ("DEF", 1), "dodge": ("DODGE", 10), "parry": ("PARRY", 10), "block": ("BLOCK", 10),
        "hit": ("SPELLHIT" if spell else "HIT", 10), "crit": ("SPELLCRIT" if spell else "CRIT", 10),
    }


def curl(url):
    r = subprocess.run(["curl", "-sS", "-f", "-m", "300", url], capture_output=True)
    if r.returncode != 0:
        raise RuntimeError(f"{url}: {r.stderr.decode(errors='replace').strip()}")
    return r.stdout


def site(path):
    time.sleep(0.3)
    return json.loads(curl(SITE + path))


def table(name, build):
    return list(csv.DictReader(io.StringIO(curl(WAGO.format(name, build)).decode("utf-8"))))


def latest_build():
    builds = json.loads(curl("https://wago.tools/api/builds"))
    return builds["wowf"][0]["version"]


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
    build = sys.argv[2] if len(sys.argv) > 2 else latest_build()
    print("Forever build", build)
    # Forever's spells by name: cooldown (the most common among its ranks) and weapon damage %
    # (players' spells only: NPCs have their own "Frostbolt" and "Execute" with other cooldowns)
    player = {r["Spell"] for r in table("SkillLineAbility", build)}
    ids = collections.defaultdict(list)
    for r in table("SpellName", build):
        if r["ID"] in player and r["Name_lang"] != "Attack":
            ids[r["Name_lang"].lower()].append(r["ID"])
    cds = {}
    for r in table("SpellCooldowns", build):
        cds[r["SpellID"]] = max(int(r["RecoveryTime"] or 0), int(r["CategoryRecoveryTime"] or 0))
    weapon = {}
    for r in table("SpellEffect", build):
        if r["Effect"] == "31":  # weapon % damage
            weapon[r["SpellID"]] = float(r["EffectBasePointsF"] or r.get("EffectBasePoints") or 0)

    def forever(name):
        found = [cds[i] for i in ids.get(name.lower(), []) if cds.get(i)]
        cd = collections.Counter(found).most_common(1)[0][0] / 1000 if found else 0
        pct = [weapon[i] for i in ids.get(name.lower(), []) if weapon.get(i)]
        return cd, (collections.Counter(pct).most_common(1)[0][0] if pct else None)

    blocks, report = [], []
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
                cells = []
                for n, sh, c in parts:
                    cpm = c * 60 / fight
                    cd, pct = forever(n)
                    spell = "true" if n.lower() in ids else "false"
                    cells.append("{ %s, %.3f, %.1f, %s, %s }" % (lua(n), sh, cpm, num(cd), spell))
                    if cd and cpm > 60 / cd + 0.05:
                        report.append(f"{key} L{lvl} {n}: site {cpm:.1f}/min, Forever cooldown {num(cd)} s caps it at {60 / cd:.1f}")
                    if pct and lvl == "60":
                        report.append(f"{key} {n}: Forever weapon damage {num(pct)}%")
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
        f.write("-- Generated by tools/guides/build.py: each spec's guide from Forever Upgrades (foreverupgrades.com),\n")
        f.write("-- with cooldowns from Forever's own spell tables. Per spec: stat weights (points per unit), the\n")
        f.write("-- rotation in priority order, and (damage specs) the rotation played out at levels 30, 50 and 60:\n")
        f.write("-- { ability, share of damage, casts a minute, Forever cooldown in s (0: none), a player spell }.\n")
        f.write("local _, ns = ...\n")
        f.write(f'ns.GUIDE = {{ build = "{stamp}", source = "Forever Upgrades", game = "{build}",\n')
        f.write("\n".join(blocks) + "\n}\n")
    print(f"wrote {out}")
    for r in sorted(set(report)):
        print("  " + r)


if __name__ == "__main__":
    main()
