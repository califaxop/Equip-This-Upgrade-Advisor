# Equip This! Next: development notes

The rebuild of Equip This!'s item evaluation: from fixed stat weights to modelled performance
(DPS, healing, tanking, PvP) of the character as it is. Built in milestones; each one is tested in
the WoW: Forever client before the next starts.

It's developed as a separate addon, **EquipThisNext** (own folder, own saved data, `/eqn`), so it
runs alongside the released Equip This! without touching it, on the `next-foundation` branch
(the weekly release only ships `release-*` branches).

## Status

| Milestone | State |
|---|---|
| 1. Foundation: compatibility layer, scanners, diagnostics | **done: 0.1.3 validated in game (level 42 Shaman, build 71091)** |
| 2. Basic evaluation | **done: validated in game (0.2.1; the tooltip %s look right to the tester)** |
| 3. Complete gear evaluation | **done: validated in game (0.3.0-0.3.3)** |
| 4. Simulation (DPS, healing, tanking, PvP) | **4a: melee DPS with abilities, imbues, procs: 0.4.0 read right in game; 0.4.1 measured in game (Windfury agrees); 0.4.2 fixes the meter's "Attack" and untrained worn weapons**; **4b (0.5.0): spells, learned rotation, HPS: built, offline tests pass (71), waiting for the in-game test**; 4c tanking threat and PvP: not started |
| 5. All classes and builds | not started |
| 6. Optimization and validation | not started |

## Layout

```
EquipThisNext/
  EquipThisNext.toc
  Core/        Bootstrap (namespace, safe calls), Events (one frame, debounce), Database (saved data), Cache (per-kind stores, fingerprints)
  API/         Compatibility (the only code that calls the game), Item, Equipment, Character, Talent, Aura, Spell
  Data/        StatDefinitions (item stat keys -> engine stats, ratings), Talents (what talents do to stats), ItemEffects (tooltip lines: stats vs effects)
  Engine/      CharacterProfile, TalentInterpreter, StatEngine, Models/Melee, Models/Survival, Evaluator (all pure Lua)
  Scanner/     Stat, Equipment, Talent, Buff, Spell, Calc scanners; CharacterScanner (builds ns.profile, event-driven)
  UI/          Tooltip (comparison on item tooltips), Diagnostics (/eqn)
  Tests/       MockAPI (a stand-in client), run.lua (runner), Cache/Compat/Profile/Scanner tests
```

Changes from the proposed structure, and why:
- `API/AuraAPI.lua` and `API/SpellAPI.lua` were added: buffs and the spellbook need API calls too, and
  all API calls live under `API/`.
- `Scanner/SpellScanner.lua` was added for learned spells and ranks.
- `Profiles/`, `Data/`, most of `Engine/` and the rest of `UI/` come with the milestones that need them,
  so there are no empty placeholder files.
- The engine is pure Lua and never calls the game. Scanners turn game data into the
  `CharacterProfile` (`Engine/CharacterProfile.lua` documents its shape), and the engine reads only that.

## Rules the code follows

- **Every game call goes through `Compat.Call`.** It looks the function up by name and calls it in
  `pcall`. Missing functions and errors come back as values, never as thrown errors.
- **Secret values never leave `Compat`.** Values the game hides are replaced by `Compat.SECRET`, so no
  other code ever holds one.
- **An item that hasn't loaded is never "zero stats".** It's recorded as `loaded = false` with
  `stats = nil`, its data is requested, and the equipment is rescanned when `ITEM_DATA_LOAD_RESULT` or
  `GET_ITEM_INFO_RECEIVED` arrives. `CharacterProfile.Validate` rejects a profile that breaks this.
- **Nothing is scanned in combat.** Changes are queued and read when combat ends. If the game hides
  stats (stats restricted), the last readable set is kept, marked `stale`, and read again as soon as
  it's allowed.
- **Talents are collected raw.** Node, entry, definition, spell, rank and max rank are kept; what
  they mean is left to the talent interpreter in milestone 2.

## API findings (Forever 1.60.1 build 71091)

Sources:
- **docs:** Blizzard's generated API documentation in the Forever UI source (`Gethe/wow-ui-source`,
  branch `forever`, commit for 1.60.1 (71091), `Blizzard_APIDocumentationGenerated`).
- **ui:** called by Blizzard's own Forever UI code (mostly `Blizzard_UIPanels_Game/Camelot`).
- **eqt:** used by the released Equip This! and working for players.

`/eqn api` shows each one's source and what happened when it was called in your client.
`Compat.KNOWN` is the full list.

### Verified, used as documented
- **Identity:** `UnitClass`, `UnitRace`, `UnitLevel`, `UnitName`, `UnitGUID`, `UnitSex`,
  `UnitEffectiveLevel`, `GetRealmName`, `GetBuildInfo`, `GetLocale`, `UnitAffectingCombat`,
  `C_SpecializationInfo.GetSpecialization`.
- **Character sheet** (all documented `SecretWhenUnitStatsRestricted`): `UnitStat`, `UnitArmor`,
  `UnitAttackPower`, `UnitRangedAttackPower`, `UnitDamage`, `UnitRangedDamage`, `UnitAttackSpeed`,
  `UnitHealthMax`, `UnitPowerType`, `UnitResistance`, `UnitDefenseSkill`, `UnitSpellHaste`,
  `GetCritChance`, `GetRangedCritChance`, `GetSpellCritChance`, `GetHitModifier`,
  `GetSpellHitModifier`, `GetRangedHitModifier`, `GetOffhandHitModifier`, `GetCombatRating`,
  `GetCombatRatingBonus`, `GetExpertise`, `GetHaste`, `GetMeleeHaste`, `GetRangedHaste`,
  `GetSpellBonusDamage(school)`, `GetSpellBonusHealing`, `GetManaRegen`, `GetSpellPenetration`,
  `GetArmorPenetration`, `GetDodgeChance`, `GetParryChance`, `GetBlockChance`, `GetShieldBlock`,
  `GetGlancingBlowChance`, `CanDualWield`.
- **The game's own stat conversions:** `GetCritChanceFromStat(stat, value)`,
  `GetSpellCritChanceFromStat`, `GetAttackPowerForStat`, `GetRangedAttackPowerForStat`,
  `GetDodgeChanceFromAttribute`, `UnitHPPerStamina`, `GetManaRegenFromSpirit`,
  `GetHealthRegenFromSpirit`. Forever's paper doll uses these to explain each stat. Milestone 2 can
  take its stat conversions (agility to crit, strength to attack power and so on) for the player's
  own class and level straight from the client instead of from tables.
- **Secrecy:** `C_Secrets.ShouldUnitStatsBeSecret`, `C_Secrets.ShouldAurasBeSecret`.
- **Items:** `C_Item.GetItemInfo` (16th return is `setID`), `GetItemInfoInstant`, `GetItemStats`,
  `IsItemDataCachedByID`, `RequestLoadItemDataByID`, `GetItemSetInfo`, `GetItemNumSockets`,
  `GetItemGem`, `GetWeaponEnchantInfo(Enum.WeaponSlot)` (returns a list of
  `{ enchantType, timeLeft, charges, enchantID, enchantIconID }`), `GetItemSpell`,
  `C_PlayerInfo.CanUseItem`.
- **Equipment (ui):** `GetInventoryItemLink`, `GetInventoryItemID`, `GetInventorySlotInfo`. These
  aren't in the generated docs, but Blizzard's Forever paper doll and containers call them.
- **Talents:** `C_ClassTalents.GetActiveConfigID`, `C_Traits.GetConfigInfo` (`treeIDs`),
  `GetTreeNodes(treeID)`, `GetNodeInfo` (`currentRank`, `ranksPurchased`, `maxRanks`,
  `activeEntry {entryID, rank}`, `entryIDs`, `groupIDs`), `GetEntryInfo` (`definitionID`,
  `maxRanks`), `GetDefinitionInfo` (`spellID`, `overrideName`).
- **Spells:** `C_Spell.GetSpellName`, `C_SpellBook.GetNumSpellBookSkillLines`,
  `GetSpellBookSkillLineInfo` (`itemIndexOffset`, `numSpellBookItems`, `shouldHide`),
  `GetSpellBookItemInfo(index, bank)` (`spellID`, `name`, `subName`, `isPassive`).
- **Auras:** `C_UnitAuras.GetAuraDataByIndex` (hidden while auras are restricted).
- **Weapon skill:** `C_SkillInfo.GetSkillLineInfoByID(skillLine)`, with Blizzard's weapon-subclass to
  skill-line map copied from `PaperDollFrameStats.lua`.
- **Events:** `PLAYER_LOGIN`, `PLAYER_ENTERING_WORLD`, `PLAYER_EQUIPMENT_CHANGED`,
  `ITEM_DATA_LOAD_RESULT`, `GET_ITEM_INFO_RECEIVED`, `TRAIT_CONFIG_UPDATED`,
  `ACTIVE_COMBAT_CONFIG_CHANGED`, `PLAYER_TALENT_UPDATE`, `CHARACTER_POINTS_CHANGED`,
  `PLAYER_LEVEL_UP`, `UNIT_STATS`, `UNIT_RESISTANCES`, `UNIT_ATTACK_POWER`, `UNIT_MAXHEALTH`,
  `COMBAT_RATING_UPDATE`, `PLAYER_DAMAGE_DONE_MODS`, `UNIT_AURA`, `SPELLS_CHANGED`,
  `PLAYER_REGEN_ENABLED`.

### Corrections found while verifying
- **`UnitDefense` is not a function on Forever.** It's only the name of an event (`UNIT_DEFENSE`).
  The defense skill is `UnitDefenseSkill(unit)` → `base, modifier`. The released Equip This! calls
  `UnitDefense`, so its defense silently falls back to 5 × level. It needs fixing in Equip This! too.
- **`IsPlayerSpell` is in neither the docs nor Blizzard's Forever UI.** Use
  `C_SpellBook.IsSpellKnown`.
- **The old talent API is gone:** `GetTalentTabInfo`, `GetNumTalentTabs` and `GetTalentInfo` aren't
  in the docs or used by Blizzard's Forever UI. Only the trait system above is used.
- **`InCombatLockdown`** isn't in the generated docs, but Blizzard's Forever UI calls it. The addon
  uses `UnitAffectingCombat("player")` first.

### Needs the in-game test
- **Talent trees:** `C_Traits.GetGroupDisplayInfoByTreeID(treeID)` → `{ groupID, displayName,
  orderIndex }` names the three trees. Its shape comes from the released Equip This!'s code, not from
  the docs. Whether each node's `groupIDs[1]` is its tree is assumed. Check with `/eqn talents`.
- **Power:** `UnitPowerMax` is not read: on Forever the player's mana is hidden from addons even out
  of combat (seen by Proc This!).
- **`GetSpellCritChance`:** the docs show no school argument on Forever. Check that it returns a
  value.
- **Combat rating constants:** the `CR_*` constants are read from the game's globals, and any that
  are missing are reported. `CR_ARMOR_PENETRATION` may not exist.
- **Spellbook:** `C_SpellBook.GetSpellBookItemInfo` reads the player bank via
  `Enum.SpellBookSpellBank.Player`.
- **Spec index:** what `C_SpecializationInfo.GetSpecialization()` returns on Forever (3-tree
  talents) is unknown. It's recorded only.


## Milestone 4: performance models (in parts)

Milestone 4 is four separate models (DPS, healing, tanking, PvP). It's built and tested in game in
parts, each on a character that can check it:
- **4a (0.4.0)**: melee DPS beyond auto attacks: weapon strikes, weapon imbues, item procs, use
  effects, and a check against the game's own damage meter.
- 4b: caster DPS and healing (spell coefficients, HPS, healing per mana, HoTs, overhealing).
- 4c: tanking threat (separate from EHP) and PvP (its own assumptions: burst, sustained,
  survivability vs players).

### 4b (0.5.0): spells, the rotation learned from your fights, healing

- **Spells** (Engine/Models/Spells.lua): every class's damage and heal spells from Forever's
  tables (Data/Generated.lua `spells`: coefficients, a DoT's per-tick coefficient and ticks, cast
  times, cooldowns, ranks' base values per level). Your highest rank of each (spellbook); its amounts
  from its description as the game shows it, else the tables; cast time, cooldown and mana from its
  tooltip. A spell that does its damage through another (Lightning Shield's bolt, 26369) uses that
  one's coefficient. Forever's coefficients are TBC-style (Lightning Bolt 0.714, Earth Shock 0.386,
  Flame Shock 0.214 + 0.1 a tick, Lightning Shield 0.267).
- Per cast: (amount + coefficient x spell damage or healing) x (1 - miss) x (1 + crit x 0.5), DoTs
  and HoTs without crits. Spell miss 4/5/6/17% vs +0-3 levels, at least 1% (Classic's, assumed).
  Not counted yet: talents that change spells (Concussion, Call of Flame, Elemental Fury...), mana.
- **How often each is cast: learned, not guessed.** `/eqn measure` turns each ability's and spell's
  damage (and healing) into casts per second of fighting: its damage / the model's damage per cast
  / the time attacking (combat time x auto-attack uptime = measured auto-attack damage / the
  model's). Kept per class and spec (`db.rotation["SHAMAN:Enhancement"]`) and used by every
  comparison; each `/eqn measure` updates it. A 0.4.x measurement is learned from at once.
  This also replaces "Stormstrike on cooldown" with how often you really press it.
- Without a measurement: a melee spec's spells aren't counted (no guess at how a hybrid mixes them;
  confidence says so); casters get DoTs kept up, cooldowns on cooldown and the best damage per
  cast time filling the rest; healers their best healing per cast time heal, all the time (both
  said to be assumed).
- **Healing**: HPS (and healing per mana) from heals, the main metric for Restoration / Holy /
  Discipline; HPS on the tooltip.

From the 0.4.2 measurement (30 fights) the model learns: Stormstrike 7.9 a minute of fighting,
Flame Shock 5.8, Earth Shock 7.2, Lightning Shield 8.2, Lightning Bolt 2.6; attacking 87% of the
combat time. Spell damage is then worth about as much per point as attack power for this shaman
(10 points: +0.68% vs +0.61% DPS).

In-game test (0.5.0):
1. `/eqn model`: "rotation: learned from your fights", and the DPS parts with your spells.
2. `/eqn abilities`: your spells' text as the game shows it.
3. Hover items with spell damage, and your Rage of the Storm vs the Flayer again.
4. `/eqn measure reset`, 15-20 fights, `/eqn measure`: the learned numbers update.
5. If you can, a few fights as Elemental or Restoration (or another class): `/eqn model`.

### 4a: what's counted, and from where

Every number comes first from what the game shows (the spell's description, resolved by the
game; a tooltip's cooldown), then from Forever's own client tables (Data/Generated.lua, built by
tools/next/build_data.py from wago.tools, product wowf, build 1.60.1.71091). A value from neither
isn't used. Expected values throughout (rate x average), no random simulation.

- **Stormstrike** (Forever's tables: 100% weapon damage, 8 s cooldown, +20% to the next nature
  spells): used on cooldown, special attack table (no glancing, no dual-wield miss), crits double.
  Item bonuses read from tooltips ("Increases the damage dealt by your Stormstrike ability by 10%":
  Rage of the Storm) multiply it. Its +20% to shocks isn't counted (spells come in 4b).
- **Windfury Weapon**: the imbue on your weapon (C_Item.GetWeaponEnchantInfo -> enchant ID ->
  Data/Generated.lua -> the spell of yours that puts it on). Chance, extra attacks and attack power
  from that spell's description; the internal cooldown from the tables (1.5 s on Forever's
  Windfury). Procs from landed main-hand hits (swings and Stormstrike): rate = lambda / (1 +
  lambda x icd). Each extra attack is a white swing with the extra attack power.
  - Forever's tables: every Windfury rank's enchant runs the same spell, 439431, whose attack power
    is 46 + 7.2 per level from 30 to 38 (103.6), while each rank's description names its own rank's
    spell (rank 2: 119 + 12.8 per level). Which one the server uses is for the measurement to tell.
  - Elemental Weapons: a spell's description already includes it (the game resolves talents into
    it). Only the game-data fallback adds it: +13/27/40% per rank (Classic's); 3/3 = 40% is
    confirmed in game (below).
- **Item procs** (IE.Model): damage ("Blasts the enemy for 80 Fire damage"; "Wounds the target for
  50 damage" as physical), extra attacks, stat buffs ("Increases your attack power by 120 for 10
  sec"). Rate: procs a minute measured on Warcraft Logs (4 items whose rate the server keeps), else
  the item's spell in the game's tables (chance per hit or procs a minute, internal cooldown), else
  **assumed once a minute, and said so** (confidence). A weapon's proc uses its own hand's hits.
  Damage procs: Classic's spell miss table (4/5/6/17%) is assumed; they don't crit.
- **Stat procs and use effects** count as their average: amount x time up (proc: 1 - e^(-rate x
  duration); use: duration / cooldown, used on cooldown).
- Comparisons: each setup's modelled effects (worn ones not replaced + the new item's), with an
  "item effects" part in the breakdown. Effects the models count no longer lower confidence.

Not counted yet: spells (shocks, Lightning Bolt, Lightning Shield's damage), mana and rage limits,
Flametongue / Frostbrand, Flurry from ability crits, extra attacks from Windfury triggering more.

### Checking it: /eqn measure

`C_DamageMeter` (Blizzard_APIDocumentationGenerated, build 71091; values secret in combat) gives
your damage per spell, per fight and over all fights since its reset. Forever has no target
dummies, so `/eqn measure` reads all fights since `/eqn measure reset` (15-20 ordinary mob fights);
`/eqn measure last` reads the last one. Short fights use an ability on cooldown at each pull too
(floor(fight / cooldown) + 1 times, not fight / cooldown): the model's share is adjusted to the
fights' lengths. `/eqn measure` compares the model's parts with it as
shares of the damage the model covers (so downtime and unmodelled spells don't skew it), lists the
spells not modelled, and marks a part "confirmed" when its share agrees within 15% (then its
unconfirmed numbers stop lowering confidence). The last 5 measurements are saved for the dump.

In-game test (0.4.0):
1. Put Windfury on your weapon. `/eqn abilities`: Stormstrike's and Windfury's text as the game
   shows them, and what the model takes from them.
2. `/eqn model`: the DPS parts (auto attack, Stormstrike, Windfury) and procs a minute.
3. `/eqn measure reset`, fight 15-20 mobs as you normally do, then `/eqn measure`.
4. Hover a few items (Rage of the Storm vs another weapon; a trinket or ring with a proc).
5. `/eqn dump` + `/reload`, send the SavedVariables file.

In-game results (0.4.0, level 42 Enhancement Shaman):
- Stormstrike's description says **110%** weapon damage (Forever's table: 100%): the game's text is
  what's used. 8 sec cooldown from its tooltip.
- Windfury rank 2's description: **2 extra attacks with 202 attack power**. 202 = (119 + 12.8 x
  (42 - 40)) x 1.40: rank 2's own spell (8236), with Elemental Weapons 3/3 = +40% already in it.
  0.4.0 added Elemental Weapons again (283): fixed in 0.4.1. Whether the server uses that or the
  shared spell 439431's 103.6 (x 1.4) is what `/eqn measure` will show.
- Model: 163 DPS = auto attack 46%, Stormstrike 25%, Windfury 29% (4.2 procs a minute).
- No target dummies in Forever: `/eqn measure` now reads all fights since a reset (0.4.1).

In-game results (0.4.1): 30 mob fights, 305 s in combat, 66,610 damage (218 DPS). By spell:
Attack 31%, Stormstrike 17%, Windfury 15%, Flame Shock 14%, Earth Shock 13%, Lightning Shield 6%,
Lightning Bolt 4%. Forever's damage meter calls auto attacks **"Attack"** (6603): 0.4.1 didn't
match it (fixed in 0.4.2). Recomputed as shares of what the model covers (63% of the damage):
- auto attack: model 42%, measured 49%
- Stormstrike: model 33%, measured 27% (casting shocks shares the global cooldown with it; fights
  of 10 s on average make the per-pull adjustment large)
- Windfury: model 25%, measured 23%: agrees. Its two attack-power readings (202 or 145) differ by
  ~5% per extra attack, too little to tell apart this way.
- The covered parts did 138 DPS over time in combat vs the model's 160 always attacking.

Also seen: wearing the 180-skill Flayer made Rage of the Storm +133% (the baseline was today's
untrained axe). 0.4.2 values weapons, worn or not, at your best weapon skill when theirs is more
than 5 below it, with today's % as a note; the comparison is now the same from either item.

## Milestone 3: complete gear evaluation (0.3.0)

Every comparison is now a complete resulting setup: which items come off, which go on, and what that
does to stats, set bonuses and weapons.

- **Weapons.** Speed comes from the tooltip's right side ("Speed 3.60"); damage per swing is its DPS x
  speed. The swing's flat part is what's left of the sheet's swing after weapon damage and attack power
  ("+N weapon damage" gear, a weapon enchant). On the real Shaman it's exactly the ring's 2.
  - **A two-hander** replaces the main hand and the off-hand.
  - **A one-hander** goes in the main hand. If you wield a two-hander, it's paired with your best shield
    or off-hand from your bags (chosen by the main metric), or with an empty off-hand, and the tooltip
    says which. If you can dual wield (`CanDualWield`), it's also tried in the off-hand.
  - **A shield or held-in-off-hand item** goes in the off-hand. If you wield a two-hander, it's paired
    with your best one-hander from your bags, or reported as needing one.
  - **Weapon skill** follows the weapon type: every weapon skill is scanned, and the game's glancing
    numbers are taken for each skill value.
  - **Dual wield:** off-hand swings at half damage, and +19 % miss on both hands (Classic; assumed for
    Forever).
  - **Ranged weapons and relics:** their stats and effects; ranged attacks aren't modelled.
- **Block only with a shield.** The sheet shows 4.84 % block with a two-hander. EHP now counts block
  only when a shield is worn, and a shield's "N Block" value counts as block value.
- **Enchants.** `GetItemStats` doesn't include them (the dump: Stamina gear 105 vs sheet 108). An
  enchant's text is the tooltip lines the enchanted item has and the same item without the enchant
  hasn't. Comparisons keep your enchant (it moves to the new item) and say so ("with your enchant on it
  (...)").
- **Set bonuses.** "(N) Set: ..." lines are read from the set's items. Before and after the swap, each
  bonus that turns on or off is gained or lost. Plain-stat bonuses count; others are listed and lower
  confidence to low.
- **Restrictions.**
  - `C_PlayerInfo.CanUseItem` false: "you can't use this".
  - Required level above yours: still compared, with "usable at level N".
  - `C_Item.GetItemUniquenessByID`: a unique item can't go in the second ring or trinket slot next to
    itself.
- **The breakdown** lists "the weapon itself (damage, speed, skill)" as one part, then each stat.

Real numbers (0.2.0 dump with 3.6 speed): the I'lalai Flayer (2.6 one-hand axe) for Rage of the Storm
(3.6 two-hand mace).
- Auto-attack DPS -11.6 %: the weapon itself -9.4 % (28.7 vs 35.6 DPS) and -12 Strength -2.4 %.
- EHP -2.9 % with an empty off-hand; +12.8 % paired with a 900-armor shield.
- A slow two-hander's real edge for Enhancement is Windfury and Stormstrike, which come with
  milestone 4.

In-game test (0.3.0):
1. `/eqn gear`: weapons show speed; enchanted items show their enchant's text.
2. Hover one-handers, shields and two-handers: the tooltip says what it pairs with and what it replaces.
3. Hover items of your Scarlet set and other belts or legs: set bonus gained or lost.
4. `/eqn compare` on a weapon: "the weapon itself" part, then stats.
5. `/eqn dump` + `/reload`: weapon speeds, enchant texts and set bonuses become test data.

In-game results (0.3.0) and the 0.3.1 fixes (each has a regression test from the dump):
- Weapon speeds, enchant texts (tooltip with vs without the enchant) and inactive set bonuses read right.
  Overlinked Chain Armor: DPS -2.0 %, EHP -0.7 %, high confidence.
- I'lalai Flayer + Savage Boar's Guard read DPS -63 %: the character's Axes skill was 180 of 210, and
  the game's glancing calculator gives 70 % glancing at -89.5 % for that. True today, misleading as a
  verdict: a weapon type below your current main-hand's skill is now valued at that skill, with
  today's % as a note ("... until it's trained up").
- "Equip: Increases your chance to block attacks with a shield by 2%." (Quillord Mail Leggings) isn't
  in GetItemStats: Equip lines the stat table lacks are now parsed as stats (IT.ExtraStats); a % line
  the item already has as a rating isn't counted twice. Block still counts only with a shield.
- An active set bonus shows as "Set: ..." without its count: the count is inferred (the lowest
  numbers from 2 no inactive line has, in order).
- Effects that change neither damage nor survivability (faster revive, mana cost, movement, mounts,
  threat...) are still listed but no longer make confidence low (IE.IRRELEVANT). Mana cost and
  threat matter again with the caster and tank models (milestone 4).
- Forever writes enchants as "Stamina +3 and Armor +24" (name first): parsed.

In-game results (0.3.1): Flayer DPS -9.5 % at trained skill (-63.4 % today, as a note); Saltscale
Girdle shows the Scarlet 2-piece lost (EHP -4.9 %: 10 Stamina of 2205 health); remaining "low"
confidences are real (Rage of the Storm's Stormstrike bonus, Gigaflux's Use: damage; milestone 4).
Quillord was still "low": Forever writes "chance to Block attacks ... by 2.0%" (capital B) and also
gives it as block rating, so the line was neither a known stat line nor extra: stat-line matching is
now case-blind (0.3.2).

## Milestone 2: basic evaluation (0.2.0)

How an item is evaluated:
1. **Start from the character sheet.** The state is the game's own numbers, buffs included. Before it's
   used for anything, the model rebuilds the sheet from the gear. On the real level-42 Shaman, the average
   swing comes out as 35.56 weapon DPS x 3.6 + 502 AP / 14 x 3.6 + 2 flat weapon damage = 259.09,
   exactly the sheet's 259.0857. Gear attack power, 73, is the sheet's AP bonus.
2. **Apply the swap as a difference:** the new item's stats minus the replaced item's, through:
   - the game's conversions measured on this character (AP per Strength and Agility, crit per Agility,
     spell crit per Intellect, dodge per Agility, health per Stamina);
   - rating to % from `GetCombatRatingBonusForCombatRatingValue`;
   - talent conversions (`Data/Talents.lua`, `Engine/TalentInterpreter.lua`).
3. **Model performance before and after.** Upgrade % = after / before - 1, separately per metric. DPS and
   EHP are never combined.
4. **Pick the best slot.** Rings and trinkets try both slots; the best is chosen on the spec's main metric
   (DPS for melee specs, else EHP).

Models:
- **Melee DPS (auto-attacks).**
  - Forever's attack table from Blizzard's Camelot UI code: miss 5.0 / 5.2 / 5.4 / 9.0 % vs a target
    0-3 levels above you, minus your hit; target dodge 5.0 / 5.5 / 6.0 / 6.5 %; 0.04 % per point of weapon
    skill vs the target's defense on hit, dodge and crit.
  - Glancing chance and penalty from `GetGlancingBlowChance` / `GetGlancingBlowPenalty`.
  - Crit is double damage. Haste is counted, and Flurry speeds up the swing after a crit (uptime
    1 - (1 - crit)^3).
  - Not yet counted (milestone 4): abilities, imbues, procs, off-hand.
- **EHP.**
  - Health / share of raw damage taken.
  - The attacker table from Blizzard's formulas: miss 5 % and crit 5 %, each moving 0.04 % per point of
    defense gap; crushing at 15+ points; your dodge, parry and block.
  - Armor from the game's `C_PaperDollInfo.GetArmorEffectiveness` (its K, measured at your armor) and
    block value.
  - 20 % magic damage split over five schools, cut by resistance. The raid mixes come later.
- **Spell damage and healing:** not modelled yet (milestone 4). Casters and healers get EHP only, and the
  tooltip says so.

Talents (`Data/Talents.lua`): only talents that change how stats turn into performance; flat bonuses are
already in the sheet.
- **Mental Dexterity 3/3 = all Intellect as attack power.** Confirmed on the sheet: base AP 429 =
  2 x 139 Str + (2 x 42 - 20) + 87 Int.
- **Mental Quickness: measured at run time.** (Sheet spell damage - gear) / Intellect; on the dump,
  (37 - 7) / 87 for both damage and healing.
- **Flurry: % from its description in game** (`C_Spell.GetSpellDescription`). If the description shows
  rank 1's number at a higher rank, the Classic table (10/15/20/25/30) gives that rank's value. This is
  marked unconfirmed.

Every result carries a confidence:
- **low:** the new or the replaced item has effects the models don't count (procs, use effects: listed
  by name, never silently zero).
- **medium:** assumptions (a Classic constant where the game gave nothing, an unconfirmed talent number,
  an unknown rating conversion, stats from before combat), and for melee, abilities not in DPS yet.
- **high:** none of the above.

Not in milestone 2:
- Weapons, shields, off-hands and relics (milestone 3).
- Set bonuses (counted, not valued: milestone 3).
- Enchants on the compared item vs yours (milestone 3).
- Separating buffs from gear: buffs stay in the baseline. `/eqn sheet` shows what's beyond gear.
- Hit rating is assumed to raise melee, ranged and spell hit like crit rating does. Not confirmed: no
  hit-rating item seen in game yet.

Real numbers from the fixture (level 42 Enhancement Shaman, glancing and armor assumed since the
0.1.0 dump has no calculators):
- vs same level: 78.5 white DPS (miss 0.04 %, dodge 5.04 %, glancing 12 %, crit 10.35 %, Flurry up
  28 %), EHP 3163.
- Per point: Strength 0.199 % DPS (= 2 AP), Intellect 0.099 % (= 1 AP, Mental Dexterity), crit rating
  0.093 %, hit 0 (the 5 % miss is already covered by +5 % hit). Stamina 0.438 % EHP.

In-game test (0.2.0):
1. `/eqn sheet`: rating conversions, glancing and armor reduction read from the game.
2. `/eqn model`: DPS and EHP with the attack table; talent lines (Flurry's % from its description).
3. `/eqn weights`: does the order look right for your character?
4. Hover items (bags, vendors, quest rewards): an "EqT Next: DPS +x% EHP +y%" line, the slot it
   replaces, and confidence. Check a few against your expectations; `/eqn compare <shift-click item>`
   for each slot and each stat's part.
5. `/eqn target 3` and `/eqn model`: vs a boss, hit should start to matter.
6. `/eqn dump` and `/reload`: the calculators' values become test data.

In-game test of 0.2.0 (level 42 Shaman, build 71091):
- **The calculators read correctly:**
  - Rating per point: crit 0.0714 % (14 per 1 %); hit, haste and expertise 0.1 %; dodge 0.0833 %;
    parry 0.0667 %; block 0.2 %.
  - Defense: 1 skill per rating point.
  - Glancing at the same level 12 % / -5 %; +1: 22 % / -5 %; +2: 32 % / -19 %; +3: 42 % / -39 %.
  - Armor reduction 24.0 % vs your level (1256 armor).
- **Talent descriptions show rank 1's numbers, whatever your rank.** Elemental Weapons 3/3 reads
  "Windfury 13 %", and Thundering Strikes 5/5 reads "1 %".
- **Flurry's description says "1 %", and is unusable.** In Forever's data its talent spell 16256 is a
  marker (aura 4, value 1); the haste is on the buff spell 16257 (aura 319 = attack speed, 10 at rank 1).
  0.2.0 took the 1 %. 0.2.1 uses the Flurry buff's own value when it's seen on you (aura `points`), else
  Classic 10/15/20/25/30 %, marked unconfirmed (regression test added).
- **The cloak's "Improves your chance to get a critical strike by 0.5 %" was listed as an uncounted
  effect.** It's its crit rating. Decimals are now matched (regression test).
- **Gear vs sheet:** Strength and attack power match exactly. Stamina: gear 105, sheet +108. Armor:
  gear 1132, sheet bonus 1118. Enchants (chest 8484, boots 8485) aren't in `GetItemStats`; they come in
  milestone 3.
- **Flurry confirmed in game (0.2.1):** the Flurry buff (16257, 3 charges) carries its value; 2/5 =
  **12 %** on Forever, not Classic's 15 %. `Data/Talents.lua` now has Forever's rank 1 (10, data) and
  rank 2 (12, seen); ranks 3-5 stay Classic until seen. A seen buff value always wins and is remembered.
  With it, same-level white DPS is 75.5 (Flurry up 27 %).
- **With the fix, on the 0.2.0 dump** (glancing and armor from the game):
  - Same level: 76.1 white DPS; 10 crit rating ≈ 9.2 AP; hit ≈ 0.
  - +3: 59.1 DPS; 10 crit rating ≈ 11.2 AP; 10 hit rating ≈ 12.1 AP.

## In-game test 1 (0.1.0, level 42 Orc Shaman, Enhancement, build 71091)

Worked:
- All 17 slots match the client, every event registered, 0 errors, no items stuck loading.
- Set 163 counted (2 pieces), enchant IDs from the links, the Windfury temp enchant (284), and the
  weapon skill (Two-Handed Maces 209/210).
- 150 stat values read; 118 spells; buffs.
- The game's conversions are confirmed: `GetAttackPowerForStat(STR, 139)` = 278,
  `GetCritChanceFromStat(AGI, 46)` = 0.03229 (a fraction: ×100 for %, as the paper doll does),
  `GetSpellCritChanceFromStat(INT, 87)` = 0.02192, `GetDodgeChanceFromAttribute()` = 0.03229.
- **Forever has combat ratings:** 7 crit rating gave +0.5% crit at level 42.
- `C_SpecializationInfo.GetSpecialization()` returned 1 for an Enhancement build, so it's not the
  talent tree. Recorded only.

Found and fixed in 0.1.1 and 0.1.2:
- **Talents:** 33 points read, but only 6 placed in a tree. The dump showed why: a Forever talent
  node's groups are mostly its **row** in the tree (groups 11350-11369, 12795, 12800 for the Shaman:
  the groups that unlock rows), and only some nodes list their tree's group (here Concussion and
  Convection → Elemental Combat 11326, Mental Dexterity, Ancestral Knowledge and Earth's Grasp →
  Enhancement 11363, Improved Healing Wave and Tidal Mastery → Restoration 11362). The trees are laid
  out side by side: Elemental x 1020-2820, Enhancement 5020-6820, Restoration 9080-10880.
  `CharacterProfile.AssignTrees` puts a node in the tree it lists, else in the tree whose column it
  sits in. With the real layout as a test fixture (`Tests/FixtureTalents.lua`, no character data) it
  gives Elemental 0, Enhancement 26, Restoration 7, the true split. Points per tree are also checked
  against the game's own count (`C_Traits.GetGroupCurrencyInfo`, as the released Equip This! uses).
- `GetRealmName()` returned an empty string. The dump key no longer has a trailing dash.
- **Combat (0.1.1 in game): confirmed.** In combat `C_Secrets.ShouldUnitStatsBeSecret()` and
  `ShouldAurasBeSecret()` are true and the crit probe reads hidden; nothing is scanned, and the
  rescan waits for combat to end. Out of combat everything reads.
- **Issues of a part not re-read were dropped** (0.1.1 showed "issues: none" while talents were
  misplaced). Fixed in 0.1.3: each issue remembers which part raised it and stays until that part is
  read again (regression test added).
- **`GetGlancingBlowChance([playerWeaponSkill], targetDefenseSkill)`** needs arguments. It's a
  calculator for the performance model, not a character-sheet value, so it's no longer scanned.
- A missing optional return (no off-hand speed) was listed as "unavailable". It no longer is.
- **`/eqn status` showed the last scan, not the present.** It now also shows live: in combat now,
  stats hidden now (with a probe read), auras hidden now, and whether a rescan is waiting for combat
  to end.

Still to check: `CR_WEAPON_SKILL` doesn't exist on Forever (reported, fine). Mana isn't read (hidden).

**0.1.3 in game: validated.** Talents: Elemental Combat 0, Enhancement 26, Restoration 7, the same as
the game's own count for each tree; 0 errors, no issues, all slots and events fine.

## Testing

Offline (no game): `python3 tools/run_next_tests.py` (needs `pip install lupa`), or
`cd EquipThisNext && lua5.1 Tests/run.lua`. The runner loads the files in the .toc's order against
`Tests/MockAPI.lua`, a stand-in client shaped like the documented API. Knobs can turn on hidden stats,
hidden auras, items that load late, missing events and API errors. 50 tests cover the cache, the
compatibility layer, link parsing, sets, talent points, profile validation, fingerprints, the full
scan, late-loading items, combat, gear and talent changes, and every `/eqn` command.

Passing tests only mean the code does what the mock describes. Whether the mock matches Forever is
what the in-game test checks.

In game (milestone 1 check):
1. `/eqn status`: client build 71091 and interface 16001, all 17 slots match, all events
   registered, 0 errors.
2. `/eqn char` and `/eqn talents`: three trees with the right points; your talents with ranks.
3. `/eqn gear`: every worn item with item level, enchant and set, nothing stuck on "loading".
4. `/eqn stats`: crit, hit, attack power, spell damage per school, resistances, defense skill, weapon
   skill, and the conversions (`critFromStat.AGI`...).
5. `/eqn api`: no missing or erroring functions.
6. Enter combat, then `/eqn status`: "stats-hidden" issue, last readable stats kept. Leave combat:
   fresh again.
7. `/eqn dump`, then `/reload`: the snapshot lands in `SavedVariables/EquipThisNext.lua`. Send it
   over; it becomes a test fixture for milestone 2.

## Known limitations (milestone 1)

- No item evaluation, tooltips or quest-reward marks yet. That's milestone 2 onward.
- **Set bonuses:** sets are counted (`setID`, name, pieces worn); what the bonuses do isn't read yet.
- **Gems:** read from the link (gem IDs) and socket counts, but Forever's Classic content may have
  no sockets.
- **Buffs** are read only out of combat. The character sheet includes them; separating gear from
  buffs is milestone 2.
- **Feral druids:** the paper doll uses a special weapon skill (3014) in forms. Not handled yet.

## Outstanding

- Milestones 1-3: done. A second class's `/eqn dump` (e.g. a rogue or warrior) would widen the fixtures.
- Milestone 4a: the in-game test and `/eqn measure` (Windfury's attack power, Elemental Weapons).
- Milestone 4b: caster DPS and healing. 4c: tanking threat, PvP.
- Released Equip This!: fix the `UnitDefense` call (see above).
