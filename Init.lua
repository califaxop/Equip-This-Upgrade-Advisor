-- Start-up, events and slash commands.
local _, ns = ...

local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LOGIN")
-- (TRAIT_*: Forever's talents are trait configs; the others are older clients')
for _, e in ipairs({ "PLAYER_EQUIPMENT_CHANGED", "CHARACTER_POINTS_CHANGED", "PLAYER_TALENT_UPDATE", "PLAYER_LEVEL_UP",
  "TRAIT_CONFIG_UPDATED", "TRAIT_TREE_CURRENCY_INFO_UPDATED" }) do
  pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" and arg1 == ns.name then
    ns.LoadDB()
    ns.CreateOptions()
  elseif event == "PLAYER_LOGIN" then
    ns.Print("loaded. Type |cffffff00/eqt|r to check your spec and weights.")
    ns.Display.HookTooltips()
    ns.Display.HookRewards()
  elseif event ~= "ADDON_LOADED" then
    ns.Score.ClearCache() -- gear, talents or level changed: usability and comparisons may differ
  end
end)

-- /eqt item <link>: everything Equip This! read from an item and how it scored it
local function Explain(link)
  local f = ns.Score.Facts(link)
  if not f then ns.Print("couldn't read that item yet (try again in a moment), or it isn't gear.") return end
  local w = ns.CurrentWeights()
  local parts = {}
  for _, k in ipairs(ns.STAT_ORDER) do
    local v = f.stats[k]
    if v then
      local shown = (v == math.floor(v)) and tostring(v) or format("%.1f", v)
      parts[#parts + 1] = format("%s %s (importance %s)", shown, ns.STAT_NAMES[k], tostring(w[k] or 0))
    end
  end
  ns.Print(link .. " - " .. (f.equipLoc or "?") .. (f.usable and "" or ", can't use it"))
  ns.Print("stats: " .. (#parts > 0 and table.concat(parts, ", ") or "none read"))
  local _, why = ns.Effects.Points(f, w)
  for _, line in ipairs(why or {}) do ns.Print("effect: " .. line) end
  local v = ns.Score.Value(link, w)
  local verdict = ns.Display.Verdict(link)
  ns.Print(format("score %.1f for %s%s", v or 0, ns.ScoringLabel(), verdict and (" - " .. verdict) or ""))
end

SLASH_EQUIPTHIS1, SLASH_EQUIPTHIS2 = "/equipthis", "/eqt"
SlashCmdList.EQUIPTHIS = function(msg)
  msg = msg or ""
  local cmd, rest = msg:match("^%s*(%S*)%s*(.-)%s*$")
  cmd = (cmd or ""):lower()
  if cmd == "guide" then
    for _, line in ipairs(ns.Rotation.Report()) do ns.Print(line) end
    return
  elseif cmd == "item" then
    local link = rest:match("|H(item:[^|]+)|h") and rest or nil
    if not link then ns.Print("usage: /eqt item <shift-click an item>") return end
    Explain(rest:match("(|c%x+|Hitem:.-|h.-|h|r)") or rest)
  elseif cmd == "spec" then
    local scale = ns.Scales.Active()
    if scale then ns.Print("scoring gear with your scale \"" .. scale .. "\" (your spec: " .. ns.SpecName(ns.SpecKey()) .. ")")
    else ns.Print("scoring gear for " .. ns.SpecName(ns.SpecKey()) .. (ns.db.spec == "auto" and " (from your talents)" or " (set in /eqt)")) end
    -- what the talents say, tree by tree
    local pts, parts = ns.TalentPoints(), {}
    for i, p in ipairs(ns.PRESETS[ns.Class()] or {}) do parts[#parts + 1] = p[1] .. " " .. ((pts and pts[i]) or 0) end
    ns.Print("talent points: " .. (pts and table.concat(parts, ", ") or "the game didn't say (spec picked as before any talents)"))
  else
    local ok, e = pcall(ns.OpenOptions)
    if not ok then ns.Print("settings error: " .. tostring(e)) end
  end
end
