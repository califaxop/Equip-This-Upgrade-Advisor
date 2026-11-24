# Equip This!: Leveling Upgrade Advisor

**Which gear is better for you while leveling, at a glance.**

Equip This! scores gear for your class and spec, marks upgrades on item tooltips, and glows the best quest reward so you never have to guess.

## Highlights
- **Forever Upgrades' numbers:** every spec's stat weights come from [Forever Upgrades](https://foreverupgrades.com)' simulator (what each stat does for the spec's DPS, HPS or tanking effective health), refreshed every week. An item scores its stats times those values, plus its effects, as a % of your whole gear: "Upgrade +2.4% DPS vs [your item]". The same % means the same in every slot.
- **Your talents count:** the site's weights assume a full level-60 talent build. Talents that change what a stat is worth (Mental Dexterity turning Intellect into attack power, Flurry, Careful Aim, Spiritual Guidance...) are checked against yours: until you have them, those stats count less, and they rise as you take them.
- **Your build:** mix damage (or healing) with survival: Damage, Leveling (the default while you level: a quarter survival), Balanced, Survival, or your own mix on a slider. Survival is your effective health: what Stamina, health and armor add to it. Tanks are the other way round: their own values are tanking, and their damage comes from the class's damage spec.
- **Your own values:** every stat's value is shown and can be typed over, or set to Higher, Highest or Ignore. Hover a stat for where its value comes from (the site's value, your talents, your change). Verdicts say "DPS", "HPS" or "EH" while your build is all one of them with no changes of yours.
- **Caps:** hit, spell hit and expertise count up to their cap (against your level while leveling, against bosses at 60), measured against your gear and talents without the item being replaced; a tank's defense counts fully up to crit immunity at 60.
- **Shift for the working:** hold Shift on an item to see where its score comes from ("Weapon DPS -8.2%, Strength +1.1%...") and any effect it doesn't count.
- **Quest rewards:** the best upgrade among the choices glows. No upgrade? The one that sells for most gets a coin.
- **Item effects count:** procs on hit, on spell cast or on crit (with the game's proc chances where it has them; about once a minute otherwise), Use effects, and "+10% Stormstrike"-style skill bonuses by that skill's share of your rotation (from Forever Upgrades' sim at your level). Enchants count too; an item with no enchant of its own is compared with yours on it, and says so.
- **Smart comparisons:** against your best item for the slot, worn or in your bags, rings and trinkets against the weaker of your two, two-handers against main hand + off hand, a one-hander replacing a two-hander paired with your best off-hand from your bags (and an off-hand's weapon DPS counting half). Optional: from level 40, only your best armor type (mail or plate) can be an upgrade.

## Quick start
1. Install and play: Equip This! works out of the box.
2. Type `/eqt` to check your spec and set your build.

## Commands
| Command | Does |
|---|---|
| `/eqt` (or `/equipthis`) | Open settings |
| `/eqt item <item>` | How an item was scored (shift-click it into the command) |
| `/eqt spec` | Which spec gear is scored for |
| `/eqt guide` | Your spec's stat priority, rotation, output split, your values, and the talents still missing from them |

## Good to know
- Stat values come from Forever Upgrades' simulations, made with level-60 gear and talents; your talents and your own changes adjust them.
- Equip-line stats (crit, hit, spell damage, mp5) are read from English item tooltips.

## Credits
Stat priorities, stat weights and rotations per spec: [Forever Upgrades](https://foreverupgrades.com). Talent builds and their texts: Forever Upgrades and Forever's own game tables. Enchants: Forever's own tables, via [wago.tools](https://wago.tools).

## Updates
New versions come out every **Wednesday at 12:00 UTC** (8 PM Philippine time, 8 AM US Eastern). Urgent fixes ship sooner.

## Feedback
Found a bug or have an idea? [Open an issue](https://github.com/califaxop/Equip-This-Upgrade-Advisor/issues/new/choose): there's a short form for each. The settings window has a "Report a bug / suggest" button with this link too.

## Recent changes
- **4.0.0:** Rebuilt around Forever Upgrades' numbers. Items score their stats times the site's weights for your spec (plus effects), as a % of your gear, with your talents scaling the stats they feed, hit / expertise / defense caps against your gear, and a build that mixes damage and survival (Damage, Leveling, Balanced, Survival or your own mix). Every stat's value can be typed over or set Higher / Highest / Ignore. Hold Shift on an item for where its score comes from. The DPS simulator and the Your DPS window are gone (and with them buffs, imbues and live stats: the same gear always scores the same).
- **3.0.2:** Enchants and imbues now count. Permanent enchants add their stats, weapon damage or proc (Crusader, +Strength, sharpening). Temporary ones (shaman imbues, poisons, stones, oils) stay on the weapon they're on: comparing your Windfury two-hander with a Rockbiter one-hander in your bags swaps Windfury for Rockbiter. An item with no enchant or imbue of its own is compared with yours on it, and the tooltip says so ("with your Crusader and Windfury 2 on it"). Rockbiter's attack power is read from its tooltip, with your talents.
- **3.0.1:** Windfury counts only while it's the imbue on your main hand (not with Rockbiter, Flametongue or none).
- **3.0.0:** Gear is now scored by your real DPS or HPS: Forever Upgrades' rotation played with your spells (from Forever's own, weekly-refreshed spell data: damage, coefficients, weapon %, cooldowns) and your live stats, so "Upgrade +2.4% DPS" is what the item does for you. A patch that changes a spell (Stormstrike's 8 sec cooldown and 100% weapon damage) counts right away. Weapons are compared as setups, and dual wielders see which hand suits a one-hander. New "Your DPS" window (button in `/eqt`, or `/eqt dps`) shows the numbers ability by ability and what each stat is worth, live; `/eqt guide` adds the stat priority. Tanks are scored by their damage (threat) plus their defensive stats by weight, and Feral by its form's claws.
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
