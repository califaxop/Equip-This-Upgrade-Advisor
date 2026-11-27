-- Start-up, events and slash commands.
local _, ns = ...

local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LOGIN")
-- (the engine reads your character itself; these change the settings it gets: level (Auto build,
-- raid at 60) and talents (spec, tanking))
for _, e in ipairs({ "PLAYER_LEVEL_UP", "TRAIT_CONFIG_UPDATED", "PLAYER_TALENT_UPDATE", "CHARACTER_POINTS_CHANGED" }) do
  pcall(ev.RegisterEvent, ev, e)
end
local pending = false
local function SyncSoon()
  if pending then return end
  pending = true
  C_Timer.After(1, function() pending = false; ns.Bridge.Sync() end)
end
ev:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" and arg1 == ns.name then
    ns.LoadDB()
    ns.CreateOptions()
  elseif event == "PLAYER_LOGIN" then
    ns.Print("loaded. Type |cffffff00/eqt|r for settings.")
    ns.Bridge.Sync()
    ns.Display.HookTooltips()
    ns.Display.HookRewards()
    -- sharing: the reminder's link opens the export window
    local FR = ns.Engine and ns.Engine.FightRecorder
    if FR then
      FR.OnRemind = ns.RemindToShare
      if EventRegistry and EventRegistry.RegisterCallback then
        EventRegistry:RegisterCallback("SetItemRef", function(_, link)
          if type(link) == "string" and link:find("^addon:EquipThis:records") then ns.ShowReport() end
        end, ns)
      end
      C_Timer.After(30, function() pcall(FR.MaybeRemind) end)   -- (records waiting from before)
    end
    -- the test build is part of Equip This! now
    local loaded = C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("EquipThisNext")
    if loaded then ns.Print("Equip This! Next (the test build) is part of Equip This! now: you can remove it from your AddOns folder.") end
  elseif event ~= "ADDON_LOADED" then
    SyncSoon()
  end
end)

local HELP = {
  "/eqt - settings",
  "/eqt item <shift-click an item> - the full working: each slot, each stat's part, effects, confidence",
  "/eqt report - your fight records to copy (if you've ticked \"Help improve Equip This!\")",
  "/eqt bug - the bug report: the form's link and a line to paste into it",
  "/eqt model - your character as Equip This! sees it: damage parts, rotation, threat, PvP, effective health",
  "/eqn - the engine's diagnostics (/eqn measure, /eqn abilities, /eqn weights, /eqn dump...)",
}

SLASH_EQUIPTHIS1, SLASH_EQUIPTHIS2 = "/equipthis", "/eqt"
SlashCmdList.EQUIPTHIS = function(msg)
  msg = msg or ""
  local cmd, rest = msg:match("^%s*(%S*)%s*(.-)%s*$")
  cmd = (cmd or ""):lower()
  local Diag = ns.Engine and ns.Engine.Diagnostics
  if cmd == "item" then
    if not rest:match("|Hitem:") and not tonumber(rest) then return ns.Print("usage: /eqt item <shift-click an item>") end
    ns.Bridge.Sync()
    if Diag then Diag.Compare(rest) end
  elseif cmd == "report" then
    ns.ShowReport()
  elseif cmd == "bug" then
    ns.ShowBugReport()
  elseif cmd == "model" then
    if Diag then Diag.Model() end
  elseif cmd == "help" then
    for _, h in ipairs(HELP) do ns.Print(h) end
  else
    local ok, e = pcall(ns.OpenOptions)
    if not ok then ns.Print("settings error: " .. tostring(e)) end
  end
end
