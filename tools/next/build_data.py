"""Builds EquipThisNext/Data/Generated.lua from WoW: Forever's own client tables (wago.tools, product
wowf): what the game's data says about item procs, weapon imbues and abilities. Every value here is
read from a table; nothing is typed in by hand. In game, the addon prefers what the game itself shows
(spell descriptions) and uses these where the game shows nothing (proc chances, internal cooldowns,
ability cooldowns).

  python tools/next/build_data.py <build> [csv folder]
    with a csv folder (one <Table>.csv per table, as wago.tools serves them), nothing is downloaded.
"""
import csv, io, os, re, sys, urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.normpath(os.path.join(HERE, "..", "..", "EquipThisNext", "Data", "Generated.lua"))
WAGO = "https://wago.tools/db2/{}/csv?build={}"
ON_EQUIP, ON_USE = "1", "0"


def table(name, build, folder):
    if folder:
        with open(os.path.join(folder, name + ".csv"), encoding="utf-8") as f:
            return list(csv.DictReader(f))
    req = urllib.request.Request(WAGO.format(name, build), headers={"User-Agent": "EquipThisNext-data-builder"})
    with urllib.request.urlopen(req, timeout=300) as r:
        return list(csv.DictReader(io.StringIO(r.read().decode("utf-8"))))


def num(x):
    try:
        return float(x)
    except (TypeError, ValueError):
        return 0.0


def fmt(x):
    x = round(float(x), 4)
    return str(int(x)) if x == int(x) else repr(x)


def main():
    build = sys.argv[1]
    folder = sys.argv[2] if len(sys.argv) > 2 else None
    T = lambda n: table(n, build, folder)
    effects = {}
    for r in T("SpellEffect"):
        if r["DifficultyID"] in ("0", ""):
            effects.setdefault(r["SpellID"], []).append(r)
    ppm = {r["ID"]: num(r["BaseProcRate"]) for r in T("SpellProcsPerMinute")}
    aura = {}
    for r in T("SpellAuraOptions"):
        if r["DifficultyID"] in ("0", ""):
            aura[r["SpellID"]] = {"chance": num(r["ProcChance"]), "icd": num(r["ProcCategoryRecovery"]) / 1000,
                                  "ppm": ppm.get(r["SpellProcsPerMinuteID"], 0)}
    levels = {r["SpellID"]: r for r in T("SpellLevels") if r.get("DifficultyID", "0") in ("0", "")}
    cds = {r["SpellID"]: r for r in T("SpellCooldowns") if r["DifficultyID"] in ("0", "")}
    names = {r["ID"]: r["Name_lang"] for r in T("SpellName")}
    descs = {r["ID"]: r.get("Description_lang") or "" for r in T("Spell")}

    # item procs: an item's on-equip spell's aura (chance per qualifying hit, procs a minute, internal cooldown)
    item_effects = {r["ID"]: r for r in T("ItemEffect")}
    procs = {}
    for r in T("ItemXItemEffect"):
        e = item_effects.get(r["ItemEffectID"])
        if not e or e["TriggerType"] != ON_EQUIP:
            continue
        a = aura.get(e["SpellID"])
        if not a or not (0 < a["chance"] < 100 or a["ppm"] > 0 or a["icd"] > 0):
            continue  # (100% with no rate: the real rate is kept on the server)
        procs[int(r["ItemID"])] = a

    # weapon imbues: temporary enchants, the spell they run while on the weapon, its chance and internal cooldown
    casts = {}
    for sid, effs in effects.items():
        for e in effs:
            if e["Effect"] in ("54", "360") and e["EffectMiscValue_0"] not in ("0", ""):
                casts.setdefault(e["EffectMiscValue_0"], []).append(int(sid))
    imbues = {}
    for r in T("SpellItemEnchantment"):
        name = r["Name_lang"] or ""
        kind = next((k for k in ("Windfury", "Flametongue", "Frostbrand", "Rockbiter") if name.startswith(k)), None)
        if not kind or num(r["Duration"]) <= 0:
            continue
        spell = r["EffectArg_0"]
        a = aura.get(spell, {})
        imb = {"kind": kind.lower(), "name": name, "spells": sorted(casts.get(r["ID"], [])),
               "chance": num(r["EffectPointsMin_0"]) or a.get("chance", 0), "icd": a.get("icd", 0), "spell": int(num(spell))}
        if kind == "Windfury":
            # extra attacks: the "$<spell>s2" its description names (an add-extra-attacks effect, type 19)
            m = re.search(r"\$(\d+)s2 extra", descs.get(spell, ""))
            for e in effects.get(m.group(1) if m else "", []):
                if e["Effect"] == "19":
                    imb["attacks"] = num(e["EffectBasePointsF"])
            # its attack power: the spell named in its description ("$8233s1 extra melee attack power")
            ap_spell = None
            for e in effects.get(spell, []):
                if e["EffectAura"] in ("4", "99") and num(e["EffectBasePointsF"]) > 0:
                    ap_spell = spell
                    lv = levels.get(spell, {})
                    imb["ap"] = {"base": num(e["EffectBasePointsF"]), "perLevel": num(e["EffectRealPointsPerLevel"]),
                                 "baseLevel": num(lv.get("BaseLevel")), "maxLevel": num(lv.get("MaxLevel"))}
                    break
        imbues[int(r["ID"])] = imb

    # abilities: weapon strikes (weapon damage %) and their cooldowns
    abilities = {}
    for sid in ("17364",):  # Stormstrike
        a = {"name": names.get(sid, "")}
        for e in effects.get(sid, []):
            if e["Effect"] == "31":
                a["weaponPct"] = num(e["EffectBasePointsF"])
            if e["Effect"] == "6" and e["EffectAura"] == "271":
                a["natureBonusPct"] = num(e["EffectBasePointsF"])
        c = cds.get(sid, {})
        a["cooldown"] = max(num(c.get("RecoveryTime")), num(c.get("CategoryRecoveryTime"))) / 1000
        abilities[int(sid)] = a

    # class spells that deal damage or heal: coefficients, ranks' base values, cast times, cooldowns
    misc = {r["SpellID"]: r for r in T("SpellMisc") if r.get("DifficultyID", "0") in ("0", "")}
    casttimes = {r["ID"]: num(r["Base"]) for r in T("SpellCastTimes")}
    durations = {r["ID"]: num(r["Duration"]) for r in T("SpellDuration")}
    SCHOOL = {1: "Physical", 2: "Holy", 4: "Fire", 8: "Nature", 16: "Frost", 32: "Shadow", 64: "Arcane"}
    class_spells = set()
    for r in T("SkillLineAbility"):
        if r["ClassMask"] not in ("0", ""):
            class_spells.add(r["Spell"])

    def parts(sid):
        """the spell's own damage/heal effects: direct and periodic"""
        out = {}
        for e in effects.get(sid, []):
            coef = num(e["EffectBonusCoefficient"])
            if e["Effect"] in ("2", "10"):  # school damage, heal
                out["kind"] = "heal" if e["Effect"] == "10" else "damage"
                out["direct"] = {"base": num(e["EffectBasePointsF"]), "perLevel": num(e["EffectRealPointsPerLevel"]),
                                 "variance": num(e["Variance"]), "coef": coef}
            elif e["Effect"] == "6" and e["EffectAura"] in ("3", "8") and num(e["EffectAuraPeriod"]) > 0:
                out.setdefault("kind", "heal" if e["EffectAura"] == "8" else "damage")
                m = misc.get(sid, {})
                d = durations.get(m.get("DurationIndex"), 0)
                out["dot"] = {"tick": num(e["EffectBasePointsF"]), "ticks": int(d // num(e["EffectAuraPeriod"])) if d > 0 else 0,
                              "coef": coef, "period": num(e["EffectAuraPeriod"]) / 1000}
        return out

    spells = {}
    for sid in class_spells:
        p_ = parts(sid)
        linked = None
        if not p_:
            m = re.search(r"\$(\d+)s1 \w+ damage", descs.get(sid, ""))
            if m and m.group(1) in effects:
                p_ = parts(m.group(1))
                linked = m.group(1)
        if not p_ or not any(x.get("coef", 0) > 0 for x in (p_.get("direct", {}), p_.get("dot", {}))):
            continue
        m = misc.get(linked or sid, {}) if linked else misc.get(sid, {})
        mm = misc.get(sid, {})
        c = cds.get(sid, {})
        lv = levels.get(sid, {})
        spells[int(sid)] = dict(p_, name=names.get(sid, ""), school=SCHOOL.get(int(num(m.get("SchoolMask"))), "?"),
                                cast=casttimes.get(mm.get("CastingTimeIndex"), 0) / 1000,
                                cooldown=max(num(c.get("RecoveryTime")), num(c.get("CategoryRecoveryTime"))) / 1000,
                                gcd=num(c.get("StartRecoveryTime")) / 1000 if c else 1.5,
                                level=num(lv.get("SpellLevel")), baseLevel=num(lv.get("BaseLevel")), maxLevel=num(lv.get("MaxLevel")),
                                linked=int(linked) if linked else None)

    L = ["-- AUTO GENERATED by tools/next/build_data.py from WoW: Forever's client tables: do not edit.",
         "-- itemProcs[itemID] = { chance = % per qualifying hit, ppm = procs a minute, icd = internal cooldown (s) }",
         "-- imbues[enchantID] = { kind, name, spells = the spells that put it on, chance, icd, spell, ap = { base,",
         "--   perLevel, baseLevel, maxLevel } }   abilities[spellID] = { weaponPct, cooldown (s), natureBonusPct }",
         "local _, ns = ...", "ns.GENERATED = {", '  build = "%s",' % build, "  itemProcs = {"]
    for i in sorted(procs):
        a = procs[i]
        L.append("    [%d] = { chance = %s, ppm = %s, icd = %s }," % (i, fmt(a["chance"]), fmt(a["ppm"]), fmt(a["icd"])))
    L.append("  },")
    L.append("  imbues = {")
    for i in sorted(imbues):
        m = imbues[i]
        ap = m.get("ap")
        aps = (", attacks = %s" % fmt(m["attacks"])) if m.get("attacks") else ""
        aps += (", ap = { base = %s, perLevel = %s, baseLevel = %s, maxLevel = %s }" % (fmt(ap["base"]), fmt(ap["perLevel"]), fmt(ap["baseLevel"]), fmt(ap["maxLevel"]))) if ap else ""
        L.append('    [%d] = { kind = "%s", name = "%s", spells = { %s }, chance = %s, icd = %s, spell = %d%s },' % (
            i, m["kind"], m["name"].replace('"', '\\"'), ", ".join(map(str, m["spells"])), fmt(m["chance"]), fmt(m["icd"]), m["spell"], aps))
    L.append("  },")
    L.append("  -- spells[spellID] = { name, kind = damage|heal, school, direct = { base, perLevel, variance, coef },")
    L.append("  --   dot = { tick, ticks, coef (per tick) }, cast, cooldown, gcd (s), level, baseLevel, maxLevel, linked }")
    L.append("  spells = {")
    def tbl(d):
        return "{ " + ", ".join("%s = %s" % (k, fmt(v)) for k, v in d.items()) + " }"
    for i in sorted(spells):
        x = spells[i]
        cells = ['name = "%s"' % x["name"].replace('"', '\\"'), 'kind = "%s"' % x["kind"], 'school = "%s"' % x["school"]]
        if "direct" in x: cells.append("direct = " + tbl(x["direct"]))
        if "dot" in x: cells.append("dot = " + tbl(x["dot"]))
        cells += ["cast = %s" % fmt(x["cast"]), "cooldown = %s" % fmt(x["cooldown"]), "gcd = %s" % fmt(x["gcd"]),
                  "level = %s" % fmt(x["level"]), "baseLevel = %s" % fmt(x["baseLevel"]), "maxLevel = %s" % fmt(x["maxLevel"])]
        if x["linked"]: cells.append("linked = %d" % x["linked"])
        L.append("    [%d] = { %s }," % (i, ", ".join(cells)))
    L.append("  },")
    L.append("  abilities = {")
    for i in sorted(abilities):
        a = abilities[i]
        L.append('    [%d] = { name = "%s", weaponPct = %s, cooldown = %s, natureBonusPct = %s },' % (
            i, a["name"], fmt(a.get("weaponPct", 0)), fmt(a["cooldown"]), fmt(a.get("natureBonusPct", 0))))
    L.append("  },")
    L.append("}")
    with open(OUT, "w", newline="\n") as f:
        f.write("\n".join(L) + "\n")
    print("item procs %d, imbues %d, abilities %d -> %s" % (len(procs), len(imbues), len(abilities), OUT))


if __name__ == "__main__":
    main()
