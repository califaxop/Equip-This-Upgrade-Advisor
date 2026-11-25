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
| 1. Foundation: compatibility layer, scanners, diagnostics | **0.1.0 tested in game (see below); 0.1.2 fixes waiting for a re-test** |
| 2. Basic evaluation | not started (waits for milestone 1's in-game test) |
| 3. Complete gear evaluation | not started |
| 4. Simulation (DPS, healing, tanking, PvP) | not started |
| 5. All classes and builds | not started |
| 6. Optimization and validation | not started |

## Layout

```
EquipThisNext/
  EquipThisNext.toc
  Core/        Bootstrap (namespace, safe calls), Events (one frame, debounce), Database (saved data), Cache (per-kind stores, fingerprints)
  API/         Compatibility (the only code that calls the game), Item, Equipment, Character, Talent, Aura, Spell
  Engine/      CharacterProfile (pure Lua: the normalized profile, validation, fingerprints)
  Scanner/     Stat, Equipment, Talent, Buff, Spell scanners; CharacterScanner (builds ns.profile, event-driven)
  UI/          Diagnostics (/eqn)
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
- **`GetGlancingBlowChance([playerWeaponSkill], targetDefenseSkill)`** needs arguments. It's a
  calculator for the performance model, not a character-sheet value, so it's no longer scanned.
- A missing optional return (no off-hand speed) was listed as "unavailable". It no longer is.
- **`/eqn status` showed the last scan, not the present.** It now also shows live: in combat now,
  stats hidden now (with a probe read), auras hidden now, and whether a rescan is waiting for combat
  to end.

Still to check: `CR_WEAPON_SKILL` doesn't exist on Forever (reported, fine). Mana isn't read (hidden).

## Testing

Offline (no game): `python3 tools/run_next_tests.py` (needs `pip install lupa`), or
`cd EquipThisNext && lua5.1 Tests/run.lua`. The runner loads the files in the .toc's order against
`Tests/MockAPI.lua`, a stand-in client shaped like the documented API. Knobs can turn on hidden stats,
hidden auras, items that load late, missing events and API errors. 27 tests cover the cache, the
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

- Milestone 1: the in-game test (above). Fix anything it shows, and add the `/eqn dump` snapshots as
  fixtures.
- Milestone 2 (after that): talent interpreter, gear-vs-buff stat separation, stat conversions from
  the game's functions, first performance models and marginal stat values, single-slot, ring and
  trinket comparisons.
- Released Equip This!: fix the `UnitDefense` call (see above).
