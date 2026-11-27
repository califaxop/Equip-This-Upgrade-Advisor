-- Equip This! 5.0 (the engine bundled into Equip This!): loads the whole addon (EquipThis.toc at the
-- repository root) on the mock game, with every UI frame call accepted, and checks the tooltip line,
-- quest rewards, settings window, commands, the opt-in records and the old settings' migration.
-- Runs only where the repository root is Equip This! 5.0 (Bridge.lua there).
local EQT = ROOT .. "../"
local f = io.open(EQT .. "Bridge.lua", "r")
if not f then OUT("  (skipped: the repository root isn't Equip This! 5.0)") return end
f:close()

-- frames for the UI: any method works; Get* return a number, Is*/Has* false, the rest the frame
local function permissive()
  local o = {}
  return setmetatable(o, { __index = function(t, k)
    if type(k) ~= "string" then return nil end
    if k:find("^Get") then return function() return 100 end end
    if k:find("^Is") or k:find("^Has") then return function() return false end end
    if k:find("^Create") then return function() return permissive() end end
    return function() return t end
  end })
end
local baseCreateFrame = CreateFrame
local function uiCreateFrame(...)
  local f = baseCreateFrame(...)
  local fallback = permissive()
  return setmetatable(f, { __index = function(_, k) return fallback[k] end })
end

local function loadEQT(db)
  MOCK.Reset()
  CreateFrame = uiCreateFrame
  UIParent = permissive(); ChatFontNormal = {}; Settings = nil; InterfaceOptions_AddCategory = function() end
  hooksecurefunc = function() end
  UISpecialFrames = {}
  format, tinsert, tremove, wipe = string.format, table.insert, table.remove, function(t) for k in pairs(t) do t[k] = nil end return t end
  EquipThisDB = db
  EquipThisEngineDB = nil
  local ns = {}
  local fh = assert(io.open(EQT .. "EquipThis.toc"))
  for line in fh:lines() do
    line = line:gsub("%s+$", "")
    if line ~= "" and not line:match("^#") then assert(loadfile(EQT .. line:gsub("\\", "/")))("EquipThis", ns) end
  end
  fh:close()
  for id in pairs(MOCK.ITEMS) do MOCK.cached[id] = true end
  MOCK.Fire("ADDON_LOADED", "EquipThis"); MOCK.Fire("PLAYER_LOGIN"); MOCK.Fire("PLAYER_ENTERING_WORLD"); MOCK.RunTimers()
  return ns
end

T.Test("5.0: Equip This! loads with the engine inside; the tooltip line comes from it", function()
  MOCK.windfury = true
  local ns = loadEQT(nil)
  T.Ok(ns.Engine and ns.Engine.bundled, "the engine, in its own namespace")
  T.Ok(ns.Engine.profile, "it scanned the character")
  T.Eq(ns.Engine.db.tree, "auto", "settings synced into the engine")
  local tt = MOCK.MakeTooltip("|cff0070dd|Hitem:1008::::::::42|h[Ring of Procs]|h|r")
  function tt:Show() end
  GameTooltip = tt   -- (Equip This! writes on the game's own tooltips)
  MOCK.tooltipHook(tt, {})
  local all = table.concat(tt.lines, "\n")
  OUT("    tooltip: " .. all:gsub("\n", " / "))
  -- the order: what it's tried with, the numbers apart, the verdict for your build (labelled)
  T.Ok(tt.lines[1] and tt.lines[1]:find("Equip This!:") and tt.lines[1]:find("vs") and tt.lines[1]:find("Band of Sets"), "1: " .. tostring(tt.lines[1]))
  T.Ok(tt.lines[2] and tt.lines[2]:find("DPS") and tt.lines[2]:find("EHP"), "2: the numbers: " .. tostring(tt.lines[2]))
  T.Ok(tt.lines[3] and (tt.lines[3]:find("Upgrade") or tt.lines[3]:find("Downgrade")) and tt.lines[3]:find("for your build %(75%% damage / 25%% survival%)"), "3: " .. tostring(tt.lines[3]))
  IsShiftKeyDown = function() return true end
  local tt2 = MOCK.MakeTooltip("|cff0070dd|Hitem:1008::::::::42|h[Ring of Procs]|h|r"); function tt2:Show() end
  GameTooltip = tt2
  MOCK.tooltipHook(tt2, {})
  local all2 = table.concat(tt2.lines, "\n")
  T.Ok(all2:find("Confidence") and all2:find("For "), "Shift: confidence and the build: " .. all2)
  IsShiftKeyDown = function() return false end
  T.Eq(ns.Engine.errors.count, 0, "no engine errors")
end)

T.Test("5.0: consumables and trade goods get no Equip This! lines; an off-hand with a two-hander still says why", function()
  MOCK.ITEMS[1020] = { "Bread of Testing", "", 0, 5, 1, 45, nil, {} }      -- a consumable
  MOCK.ITEMS[1021] = { "Silk of Testing", "", 7, 5, 1, 30, nil, {} }       -- a trade good
  MOCK.ITEMS[1022] = { "Bag of Testing", "INVTYPE_BAG", 1, 0, 1, 30, nil, {} }
  local ns = loadEQT(nil)
  for _, id in ipairs({ 1020, 1021, 1022 }) do
    local link = "|cffffffff|Hitem:" .. id .. "::::::::42|h[x]|h|r"
    T.Eq(ns.Bridge.Compare(link), nil, "item " .. id)
    T.Eq(ns.Display.Lines(link), nil, "no lines: item " .. id)
  end
  -- a shield, while you wield a two-hander with no one-hander in your bags: the one line that explains
  local c = ns.Bridge.Compare("|cff0070dd|Hitem:1011::::::::42|h[Shield of Bags]|h|r")
  if c and c.kind ~= "twohand" then OUT("    (shield compared with a one-hander from the bags: " .. tostring(c.kind) .. ")") end
  MOCK.ITEMS[1020], MOCK.ITEMS[1021], MOCK.ITEMS[1022] = nil, nil, nil
end)

T.Test("5.0: the slider mixes the verdict; the numbers stay apart", function()
  local ns = loadEQT(nil)
  local link = "|cff0070dd|Hitem:1008::::::::42|h[Ring of Procs]|h|r"
  ns.Bridge.SetBuild("damage"); ns.Bridge.Sync()
  local a = ns.Bridge.Compare(link)
  ns.Bridge.SetBuild("survival"); ns.Bridge.Sync()
  local b = ns.Bridge.Compare(link)
  T.Near(a.pct, a.metrics.dps, 1e-9, "Damage: the DPS %")
  T.Near(b.pct, b.metrics.ehp, 1e-9, "Survival: the EHP %")
  ns.Bridge.SetMix(0.4); ns.Bridge.Sync()
  local c = ns.Bridge.Compare(link)
  T.Near(c.pct, 0.6 * c.metrics.dps + 0.4 * c.metrics.ehp, 1e-9, "your mix")
  T.Eq(ns.Display.BuildMix(), "60% damage / 40% survival")
  ns.Bridge.SetBuild("damage"); T.Eq(ns.Display.BuildMix(), "all damage")
end)

T.Test("5.0: settings window, commands, quest rewards", function()
  local ns = loadEQT(nil)
  local okO, eO = pcall(ns.OpenOptions)
  T.Ok(okO, "the settings window builds: " .. tostring(eO))
  PRINTS = {}; SlashCmdList.EQUIPTHIS("item |cff0070dd|Hitem:1008::::::::42|h[Ring of Procs]|h|r")
  T.Ok(#PRINTS > 0, "/eqt item")
  PRINTS = {}; SlashCmdList.EQUIPTHIS("model"); T.Ok(table.concat(PRINTS, " "):find("DPS"), "/eqt model")
  PRINTS = {}; SlashCmdList.EQUIPTHIS("help"); T.Ok(#PRINTS >= 4, "/eqt help")
  T.Ok(pcall(SlashCmdList.EQUIPTHIS, "report"), "/eqt report")
  GetNumQuestChoices = function() return 2 end
  GetQuestItemLink = function(_, i) return i == 1 and "|cff0070dd|Hitem:1008::::::::42|h[Ring of Procs]|h|r" or "|cff0070dd|Hitem:1003::::::::42|h[Ring of Sets]|h|r" end
  ns.db.rewards = true
  T.Ok(pcall(ns.Display.MarkRewards), "quest rewards marked without errors")
  T.Eq(ns.Engine.errors.count, 0)
end)

T.Test("5.0: opt-in fight records: off by default; on, anonymous lines to copy", function()
  local ns = loadEQT(nil)
  T.Eq(ns.Engine.db.share, false); T.Eq(ns.Engine.db.learn, true)
  ns.Engine.db.share = true
  MOCK.meter = { id = 500, duration = 30, spells = { [6603] = 3000, [17364] = 1200, [403] = 500 } }
  MOCK.Fight(); MOCK.RunTimers()
  local text, n = ns.Engine.FightRecorder.ReportText()
  T.Eq(n, 1)
  T.Ok(text:find("EQT5|") and text:find("SHAMAN"), text)
  local okR, eR = pcall(ns.ShowReport)
  T.Ok(okR, "the export window: " .. tostring(eR))
  -- the reminder: a chat line whose link opens the export window
  local cb
  EventRegistry = { RegisterCallback = function(_, ev, fn) if ev == "SetItemRef" then cb = fn end end }
  local ns2 = loadEQT(nil)
  T.Ok(cb, "the link handler")
  PRINTS = {}; ns2.RemindToShare(30)
  local msg = table.concat(PRINTS, " ")
  T.Ok(msg:find("30 new fight logs to submit") and msg:find("|Haddon:EquipThis:records|h", 1, true), msg)
  local opened = false
  ns2.ShowReport = function() opened = true end
  cb(nil, "addon:EquipThis:records")
  T.Ok(opened, "clicking it opens the export window")
  ns2.Engine.db.share = true
  MOCK.meter = { id = 900, duration = 30, spells = { [6603] = 3000 } }
  MOCK.Fight(); MOCK.RunTimers()
  T.Eq(ns2.Engine.FightRecorder.MarkReported(), 1, "I reported this")
  EventRegistry = nil
end)

T.Test("5.0: 4.x settings: the old scoring's are dropped, the rest kept", function()
  local ns = loadEQT({ spec = "SHAMAN:2", priorities = { ["SHAMAN:2"] = { build = "leveling" } }, tooltip = false, raids = { ["X-Y"] = "mc" } })
  T.Eq(ns.db.spec, "auto"); T.Eq(ns.db.priorities, nil); T.Eq(ns.db.tooltip, false); T.Eq(ns.db.raids["X-Y"], "mc")
end)

T.Test("5.0: a one-hander paired with a shield from your bags: the pairing first, no repeated note", function()
  local ns = loadEQT(nil)
  MOCK.BAGS = { [1] = "|cff0070dd|Hitem:1011::::::::42|h[Shield of Bags]|h|r" }
  MOCK.Fire("BAG_UPDATE_DELAYED"); MOCK.RunTimers()
  ns.Bridge.Sync()
  local tt = MOCK.MakeTooltip("|cff0070dd|Hitem:1010::::::::42|h[Blade of Bags]|h|r"); function tt:Show() end
  GameTooltip = tt
  MOCK.tooltipHook(tt, {})
  local all = table.concat(tt.lines, " / ")
  T.Ok(tt.lines[1]:find("paired with") and tt.lines[1]:find("Shield of Bags") and tt.lines[1]:find("%(bags%)"), "1: " .. all)
  T.Ok(tt.lines[2]:find("DPS") and tt.lines[2]:find("EHP"), "2: " .. all)
  T.Ok(tt.lines[3]:find("vs") and tt.lines[3]:find("Axe of Testing") and tt.lines[3]:find("for your build"), "3: " .. all)
  T.Ok(not all:find("from your bags"), "the pairing isn't repeated as a note: " .. all)
  MOCK.BAGS = {}
end)
