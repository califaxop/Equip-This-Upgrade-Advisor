# Equip This!: Leveling Upgrade Advisor

**Which gear is better for you while leveling, at a glance.**

Equip This! scores gear for your class and spec, marks upgrades on item tooltips, and glows the best quest reward so you never have to guess.

## Highlights
- **Quest rewards:** the best upgrade among the choices glows. No upgrade? The one that sells for most gets a coin.
- **Tooltips:** "Upgrade +12% (Elemental)", "Downgrade", "Equipped" or "Can't use it", compared with what you wear.
- **Melee: your real damage.** For warriors, rogues, Retribution paladins and Enhancement shamans, gear is scored by what it does to your melee damage: "Upgrade +2.4% damage". Your attack power, crit, hit and haste come from the game, live, with Forever's own conversions (what Strength and Agility give your class); stats that aren't damage (Stamina, Intellect, armor...) count through your weights, and item effects as the share of your output they add. Your output is split the way your Skill Weights say: white hits move with your damage per second; weapon strikes (Stormstrike, Mortal Strike, Sinister Strike...) with one main-hand hit, so a slow, heavy weapon makes them hit much harder; spells don't change with melee gear. `/eqt model` shows the numbers next to your character sheet's.
- **Weapons as setups:** a one-hander against your two-hander comes with your best off-hand from your bags (a shield, or a second weapon if you dual wield); if you own none, it's compared on its own. Dual wielders see whether a one-hander is better in the main hand or the off hand.
- **Your spec:** picked from your talents, or set it yourself. Every class and spec has stat weights, which you can tune on a simple 0-5 scale.
- **Your own scales:** make named stat scales for your theorycrafting, import Pawn-style strings from guides, export yours to share.
- **Item effects count:** procs on hit, on spell cast or on crit (about once a minute unless the item says otherwise; procs tied to one skill go off with that skill's casts) and Use effects: damage as DPS (weapon DPS for melee, spell damage for casters), stat buffs ("+300 Attack Power", "+5% crit chance", "+132 spell damage") by how long they're up, mana as mana per 5, haste as extra swings or casts, weapon skill ("Increased Swords +5") as +0.04% hit and crit per point (and softer glancing blows on raid bosses at 60) when you use that weapon. Procs when you're hit and on kills aren't counted. Checked against every effect line on Forever's gear.
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
| `/eqt model` | The melee damage model's numbers next to your character sheet (`/eqt model off` / `on`) |

## Good to know
- Stat weights are a starting point, not a simulation: tune them in `/eqt` to taste. (Melee specs: the damage stats come from the damage model; your weights still decide stats that aren't damage.)
- The damage model reckons with an enemy your own level, with Classic's rules for its side: 5% miss (+19% on white swings when dual wielding), 5% dodge, 10% glancing blows, crits for double damage, the off hand for half.
- Equip-line stats (crit, hit, spell damage, mp5) are read from English item tooltips.

## Updates
New versions come out every **Wednesday at 12:00 UTC** (8 PM Philippine time, 8 AM US Eastern). Urgent fixes ship sooner.

## Feedback
Found a bug or have an idea? [Open an issue](https://github.com/califaxop/Equip-This-Upgrade-Advisor/issues/new/choose): there's a short form for each. The settings window has a "Report a bug / suggest" button with this link too.

## Recent changes
- **2.5.0:** Melee gear is scored by your real damage: a melee damage model built on your live numbers from the game (attack power, crit, hit, haste, and Forever's own Strength / Agility conversions), so every verdict is in one currency: "Upgrade +2.4% damage". No more inflated percentages between two weak items (shoulders showed +126%; now +0.8% damage). Weapons are compared as setups: a one-hander against your two-hander comes with your best off-hand, and dual wielders see which hand it suits. `/eqt model` shows the model next to your character sheet. Haste rating on gear now counts.
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
