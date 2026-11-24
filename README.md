# Equip This!: Leveling Upgrade Advisor

**Which gear is better for you while leveling, at a glance.**

Equip This! scores gear for your class and spec, marks upgrades on item tooltips, and glows the best quest reward so you never have to guess.

## Highlights
- **Quest rewards:** the best upgrade among the choices glows. No upgrade? The one that sells for most gets a coin.
- **Tooltips:** "Upgrade +2.4% (Elemental)", "Downgrade", "Equipped" or "Can't use it", compared with what you wear. The % is of your whole gear's score, so it means the same in every slot: +2.4% is 2.4% stronger overall.
- **Stat values and rotations from Forever Upgrades:** every spec's stats are valued as on [Forever Upgrades](https://foreverupgrades.com), made for WoW: Forever. Items that improve a skill count by that skill's share of your damage in Forever Upgrades' rotation for your spec, as its simulator plays it at your level (levels 30, 50 and 60, blended between). `/eqt guide` shows your spec's rotation and damage split.
- **Real proc rates:** "Chance on hit" items use their proc chance from the game's own tables where it has one (Ironfoe: 6% per swing); others count as about once a minute.
- **Made for leveling:** the default goal, Auto, values what keeps you going while you level (Stamina and Health x3; Armor, Intellect, Spirit and mana per 5 x2, as Pawn Forever does) and switches to Forever Upgrades' damage values by itself at the level cap.
- **Your priorities:** pick another goal in `/eqt` (Leveling, Damage, Survival, Mana, Balanced), then set any stat to Ignore, Normal, Higher or Highest on top of it: your changes stay when the goal changes. "Upgrade +6% (Enhancement, Survival)". Normal is Forever Upgrades' value; Highest makes a stat worth more than every Normal one, so items with more of it win.
- **Your spec:** picked from your talents, or set it yourself.
- **Item effects count:** procs on hit, on spell cast or on crit (about once a minute unless the item says otherwise; procs tied to one skill go off with that skill's casts) and Use effects: damage as DPS (weapon DPS for melee, spell damage for casters), stat buffs ("+300 Attack Power", "+5% crit chance", "+132 spell damage") by how long they're up, mana as mana per 5, haste as extra swings or casts, weapon skill ("Increased Swords +5") as +0.04% hit and crit per point (and softer glancing blows on raid bosses at 60) when you use that weapon. Procs when you're hit and on kills aren't counted. Checked against every effect line on Forever's gear.
- **Your skills:** items that name a skill ("+10% Stormstrike", "+1% crit chance of Healing Wave", "-1 sec cooldown", "+3 sec duration", "+30 healing", "your Shock spells"), however they're worded, count by that skill's share of your output, so +10% to a skill that's 20% of your damage is +2% output, valued like +2% crit. Skills outside your rotation count for nothing. `/eqt item` shows the working.
- **Smart comparisons:** against your best item for the slot, worn or in your bags ("vs [Helm] (in your bags)"), rings and trinkets against the weaker of your best two, two-handers against main hand + off hand. Optional: from level 40, only your best armor type (mail or plate) can be an upgrade.

## Quick start
1. Install and play: Equip This! works out of the box.
2. Type `/eqt` to check your spec and set your priorities.

## Commands
| Command | Does |
|---|---|
| `/eqt` (or `/equipthis`) | Open settings |
| `/eqt item <item>` | How an item was scored (shift-click it into the command) |
| `/eqt spec` | Which spec gear is scored for |
| `/eqt guide` | Your spec's rotation and damage split from Forever Upgrades |

## Good to know
- Stat values come from Forever Upgrades' simulations; your priorities move them up or down.
- Equip-line stats (crit, hit, spell damage, mp5) are read from English item tooltips.

## Credits
Rotations, damage splits and stat weights per spec: [Forever Upgrades](https://foreverupgrades.com).

## Updates
New versions come out every **Wednesday at 12:00 UTC** (8 PM Philippine time, 8 AM US Eastern). Urgent fixes ship sooner.

## Feedback
Found a bug or have an idea? [Open an issue](https://github.com/califaxop/Equip-This-Upgrade-Advisor/issues/new/choose): there's a short form for each. The settings window has a "Report a bug / suggest" button with this link too.

## Recent changes
- **2.6.0:** Made for leveling: a new default goal, Auto, raises Stamina and Health (x3) and Armor, Intellect, Spirit and mana per 5 (x2) while you level, and switches to damage values by itself at the level cap. Your stat changes now sit on top of any goal (Default puts a stat back to the goal's). Upgrades are measured against your best item, worn or in your bags, so an item worse than one you carry isn't an upgrade. New option: from level 40, only mail or plate can be an upgrade (off by default). Expertise, Spell Penetration and health per 5 sec now count.
- **2.5.0:** Stat weights for every spec now come from Forever Upgrades, made for WoW: Forever (Health counts too: items with "+Health"). Skill Weights are gone: items that improve a skill ("+10% Stormstrike") count by that skill's share of your damage in Forever Upgrades' rotation for your spec at your level; `/eqt guide` shows it. Upgrades are now a % of your whole gear, so they mean the same in every slot: no more +126% shoulders between two weak items. Haste rating counts. New: priorities instead of 0-5 weights and custom scales: pick a goal (Damage, Survival, Mana, Balanced) or set stats to Ignore / Normal / Higher / Highest; hover a stat in `/eqt` for what it's worth (earlier weight edits and custom scales are cleared once). "Chance on hit" procs use the game's real proc chances where it has them.
- **2.4.2:** Fixed: an item read before the game had loaded its text (often right after login) was scored without its effects, like a weapon's "+10% Stormstrike", and kept that way for the whole session, so comparisons with it were off (a one-hander showed as -32% against Rage of the Storm instead of -41%). Such a read is no longer kept: the item is read again until its text is there.
- **2.4.1:** Fixed: hit, crit, spell hit / crit, dodge, parry and block were read 10 times too high on many items (WoW: Forever lists "+1% hit" as 10 hit rating), so items with them looked far better than they are (a staff with +1% hit beat a much stronger two-hander). The item's own "by 1.0%" line is used now, and a bare rating is turned into a % the way the game does for you.
- **2.4.0:** The settings window follows EllesmereUI's style when it's installed (painted by its own skinning API: your theme, accent colour and font).
- **2.3.0:** Hover a stat in `/eqt` to see what its weight is worth (e.g. "+1% Crit (3.75) is worth as much as +11.7 Strength"). Item effects now count: damage procs as weapon DPS, stat procs and Use effects (including % crit and hit buffs) by uptime. New Skill Weights in `/eqt`: your skills with relative weights and the share of your output each makes up (each spec starts with a suggested list, saved with your scales; add as many as you like), and items that improve a listed skill count by its share. `/eqt item` shows each estimate. Hit and crit worded "hit chance by 1.0%" / "crit chance by 1%" are read too.
- **2.2.2:** Fixed "Auto: from my talents": it now reads Forever's talent system, so your spec follows the tree you put the most points in (before, it always used your class's leveling default). `/eqt spec` shows the points per tree.
- **2.2.1:** Native look: the settings use the game's own tooltip border in bronze (without FlareUI style).
- **2.2.0:** Tooltips say what an item is measured against ("Downgrade -30% vs Seal of Sylvanas"), and your worn rings and trinkets say which is the weaker one (the one a new one replaces). The line now also shows on the comparison tooltips.
- **2.1.0:** Stat weights are now a simple 0-5 importance scale for every stat (decimals OK); your edits convert automatically. Custom scales: your own stat weights, with Pawn-style import and export (`/eqt` > Your scale), rename them, and a Yes/No check before deleting one.
- **2.0.0:** Gearsight is now **Equip This!**, the leveling upgrade advisor (from the makers of Proc This!). New folder and commands (`/eqt`); the CurseForge app removes the old Gearsight folder for you (manual installs: delete it yourself). Your stat weights start fresh once.
- **1.1.1:** Says hello on login ("Type /eqt to check your spec and weights").
- **1.1.0:** Gearwise is now **Equip This!** (another addon shared the old name and folder). New folder and commands (`/eqt`).
- **1.0.0:** First release: upgrade verdicts on item tooltips and the best quest reward highlighted, for every class and spec.
