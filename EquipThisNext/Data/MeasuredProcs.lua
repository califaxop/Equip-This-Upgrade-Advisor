-- Procs a minute measured on Warcraft Logs for items whose rate the game keeps on its server (their
-- client tables say 100% per hit). Source: Classic Era 40-player raids (MC, BWL, AQ40, Naxxramas),
-- recent public fights, Nov 2026: procs per minute of fight for players wearing the item (the same
-- measurement the released Equip This! 4.4.0 uses).
local _, ns = ...
ns.MEASURED_PPM = {
  [13040] = 2.26,   -- Heartseeking Crossbow
  [19287] = 3.25,   -- Darkmoon Card: Heroism
  [19289] = 2.24,   -- Darkmoon Card: Maelstrom
  [23221] = 3.27,   -- Misplaced Servo Arm
}
