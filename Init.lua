-- Start-up, events and slash commands.
local _, ns = ...

local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LOGIN")
for _, e in ipairs({ "PLAYER_EQUIPMENT_CHANGED", "CHARACTER_POINTS_CHANGED", "PLAYER_TALENT_UPDATE", "PLAYER_LEVEL_UP" }) do
  pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" and arg1 == ns.name then
    ns.LoadDB()
    ns.CreateOptions()
  elseif event == "PLAYER_LOGIN" then
    ns.Display.HookTooltips()
    ns.Display.HookRewards()
  elseif event ~= "ADDON_LOADED" then
    ns.Score.ClearCache() -- gear, talents or level changed: usability and comparisons may differ
  end
end)

-- /gsight item <link>: everything Gearsight read from an item and how it scored it
local function Explain(link)
  local f = ns.Score.Facts(link)
  if not f then ns.Print("couldn't read that item yet (try again in a moment), or it isn't gear.") return end
  local key = ns.SpecKey()
  local w = ns.Weights(key)
  local parts = {}
  for _, k in ipairs(ns.STAT_ORDER) do
    if f.stats[k] then parts[#parts + 1] = format("%s %s (x%s)", tostring(f.stats[k]), ns.STAT_NAMES[k], tostring(w[k] or 0)) end
  end
  ns.Print(link .. " - " .. (f.equipLoc or "?") .. (f.usable and "" or ", can't use it"))
  ns.Print("stats: " .. (#parts > 0 and table.concat(parts, ", ") or "none read"))
  local v = ns.Score.Value(link, w)
  local verdict = ns.Display.Verdict(link)
  ns.Print(format("score %.1f for %s%s", v or 0, ns.SpecName(key), verdict and (" - " .. verdict) or ""))
end

SLASH_GEARSIGHT1, SLASH_GEARSIGHT2 = "/gsight", "/gearsight"
SlashCmdList.GEARSIGHT = function(msg)
  msg = msg or ""
  local cmd, rest = msg:match("^%s*(%S*)%s*(.-)%s*$")
  cmd = (cmd or ""):lower()
  if cmd == "item" then
    local link = rest:match("|H(item:[^|]+)|h") and rest or nil
    if not link then ns.Print("usage: /gsight item <shift-click an item>") return end
    Explain(rest:match("(|c%x+|Hitem:.-|h.-|h|r)") or rest)
  elseif cmd == "spec" then
    ns.Print("scoring gear for " .. ns.SpecName(ns.SpecKey()) .. (ns.db.spec == "auto" and " (from your talents)" or " (set in /gsight)"))
  else
    local ok, e = pcall(ns.OpenOptions)
    if not ok then ns.Print("settings error: " .. tostring(e)) end
  end
end
