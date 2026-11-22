# Equip This!: Leveling Upgrade Advisor

**Which gear is better for you while leveling, at a glance.**

Equip This! scores gear for your class and spec, marks upgrades on item tooltips, and glows the best quest reward so you never have to guess.

## Highlights
- **Quest rewards:** the best upgrade among the choices glows. No upgrade? The one that sells for most gets a coin.
- **Tooltips:** "Upgrade +12% (Elemental)", "Downgrade", "Equipped" or "Can't use it", compared with what you wear.
- **Your spec:** picked from your talents, or set it yourself. Every class and spec has stat weights, which you can tune on a simple 0-5 scale.
- **Your own scales:** make named stat scales for your theorycrafting, import Pawn-style strings from guides, export yours to share.
- **Item effects count:** procs on hit or on spell cast (about once a minute unless the item says otherwise) and Use effects: damage as DPS (weapon DPS for melee, spell damage for casters), stat buffs ("+300 Attack Power", "+5% crit chance", "+132 spell damage") by how long they're up, mana as mana per 5, haste as extra swings or casts.
- **Your skills:** list the skills you use under Skill Weights in `/eqt`, weighted 0-5 by how much of your damage each does (each spec starts with a suggested list; add as many as you like). Each skill's share of your output is shown; items that name one ("+10% Stormstrike", "+1% crit chance of Healing Wave", "-1 sec cooldown", "+3 sec duration", "+30 healing", "your Shock spells"), however they're worded, count by that share, so +10% to a skill that's 20% of your damage is +2% output, valued like +2% crit. Unlisted skills count for nothing. `/eqt item` shows the working.
- **Smart comparisons:** rings and trinkets against your weaker one, two-handers against main hand + off hand.

## Quick start
1. Install and play: Equip This! works out of the box.
2. Type `/eqt` to check your spec and tune the weights.

## Commands
| Command | Does |
|---|---|
| `/eqt` (or `/equipthis`) | Open settings |
| `/eqt item <item>` | How an item was scored (shift-click it into the command) |
| `/eqt spec` | Which spec gear is scored for |

## Good to know
- Stat weights are a starting point, not a simulation: tune them in `/eqt` to taste.
- Equip-line stats (crit, hit, spell damage, mp5) are read from English item tooltips.

## Updates
New versions come out every **Wednesday at 12:00 UTC** (8 PM Philippine time, 8 AM US Eastern). Urgent fixes ship sooner.

## Feedback
Found a bug or have an idea? [Open an issue](https://github.com/califaxop/Equip-This-Upgrade-Advisor/issues/new/choose): there's a short form for each. The settings window has a "Report a bug / suggest" button with this link too.

## Recent changes
- **2.3.0:** Hover a stat in `/eqt` to see what its weight is worth (e.g. "+1% Crit (3.75) is worth as much as +11.7 Strength"). Item effects now count: damage procs as weapon DPS, stat procs and Use effects (including % crit and hit buffs) by uptime. New Skill Weights in `/eqt`: your skills with relative weights and the share of your output each makes up (each spec starts with a suggested list, saved with your scales; add as many as you like), and items that improve a listed skill count by its share. `/eqt item` shows each estimate. Hit and crit worded "hit chance by 1.0%" / "crit chance by 1%" are read too.
- **2.2.2:** Fixed "Auto: from my talents": it now reads Forever's talent system, so your spec follows the tree you put the most points in (before, it always used your class's leveling default). `/eqt spec` shows the points per tree.
- **2.2.1:** Native look: the settings use the game's own tooltip border in bronze (without FlareUI style).
- **2.2.0:** Tooltips say what an item is measured against ("Downgrade -30% vs Seal of Sylvanas"), and your worn rings and trinkets say which is the weaker one (the one a new one replaces). The line now also shows on the comparison tooltips.
- **2.1.0:** Stat weights are now a simple 0-5 importance scale for every stat (decimals OK); your edits convert automatically. Custom scales: your own stat weights, with Pawn-style import and export (`/eqt` > Your scale), rename them, and a Yes/No check before deleting one.
- **2.0.0:** Gearsight is now **Equip This!**, the leveling upgrade advisor (from the makers of Proc This!). New folder and commands (`/eqt`); the CurseForge app removes the old Gearsight folder for you (manual installs: delete it yourself). Your stat weights start fresh once.
- **1.1.1:** Says hello on login ("Type /eqt to check your spec and weights").
- **1.1.0:** Gearwise is now **Equip This!** (another addon shared the old name and folder). New folder and commands (`/eqt`).
- **1.0.0:** First release: upgrade verdicts on item tooltips and the best quest reward highlighted, for every class and spec.
