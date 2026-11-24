-- Start-up, events and slash commands.
local _, ns = ...

local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LOGIN")
-- (TRAIT_*: Forever's talents are trait configs; the others are older clients')
pcall(ev.RegisterEvent, ev, "BAG_UPDATE_DELAYED") -- (your bags changed: your best owned items may have)
for _, e in ipairs({ "PLAYER_EQUIPMENT_CHANGED", "CHARACTER_POINTS_CHANGED", "PLAYER_TALENT_UPDATE", "PLAYER_LEVEL_UP",
  "TRAIT_CONFIG_UPDATED", "TRAIT_TREE_CURRENCY_INFO_UPDATED" }) do
  pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, event, arg1)
  if event == "BAG_UPDATE_DELAYED" then
    ns.Score.ForgetBags()
    return
  end
  if event == "ADDON_LOADED" and arg1 == ns.name then
    ns.LoadDB()
    ns.CreateOptions()
  elseif event == "PLAYER_LOGIN" then
    ns.Print("loaded. Type |cffffff00/eqt|r for your spec and build.")
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
      parts[#parts + 1] = format("%s %s (x%s)", shown, ns.STAT_NAMES[k], ns.Short(w[k] or 0))
    end
  end
  ns.Print(link .. " - " .. (f.equipLoc or "?") .. (f.usable and "" or ", can't use it"))
  ns.Print("stats: " .. (#parts > 0 and table.concat(parts, ", ") or "none read"))
  local _, why = ns.Effects.Points(f, w)
  for _, line in ipairs(why or {}) do ns.Print("effect: " .. line) end
  local verdict, vs = ns.Display.Verdict(link)
  if verdict and vs then verdict = verdict .. " " .. vs end
  ns.Print(format("for %s%s", ns.ScoringLabel(), verdict and (": " .. verdict) or ""))
  local c = ns.Score.Compare(link)
  if c and c.parts then
    local p = ns.Display.Parts(c, 8)
    if #p > 0 then ns.Print("from: " .. table.concat(p, ", ")) end
  end
end

-- /eqt guide: the spec's priority, rotation, values and your talents' effect on them
local function Guide()
  for _, line in ipairs(ns.Rotation.Report()) do ns.Print(line) end
  local key = ns.SpecKey()
  local w = ns.Weights(key)
  local list = {}
  for _, k in ipairs(ns.STAT_ORDER) do
    if (w[k] or 0) > 0 then list[#list + 1] = { k, w[k] / (ns.NORM[k] or 1) } end
  end
  table.sort(list, function(a, b) return a[2] > b[2] end)
  local bits = {}
  for _, e in ipairs(list) do bits[#bits + 1] = format("%s %s", ns.STAT_NAMES[e[1]]:gsub(" %%$", ""), ns.Short(w[e[1]])) end
  ns.Print("values (" .. ns.ScoringLabel() .. "): " .. table.concat(bits, ", "))
  for _, side in ipairs(ns.Score.Sides()) do
    if side.kind == "points" and side.share > 0 then
      ns.Print(format("%s (%d%% of your build): you score %d points, %d from your character (base stats, level, talents) and %d from your gear; an item's %% is of that",
        side.label, side.share * 100 + 0.5, side.total, side.base or 0, (side.total or 0) - (side.base or 0)))
    end
  end
  local _, why = ns.Talents.Factors(key)
  for _, t in ipairs(why) do
    ns.Print(format("talent: %s %d/%d - %s counts less until you have it", t[2], t[3], t[4], ns.STAT_NAMES[t[1]] or t[1]))
  end
end

SLASH_EQUIPTHIS1, SLASH_EQUIPTHIS2 = "/equipthis", "/eqt"
SlashCmdList.EQUIPTHIS = function(msg)
  msg = msg or ""
  local cmd, rest = msg:match("^%s*(%S*)%s*(.-)%s*$")
  cmd = (cmd or ""):lower()
  if cmd == "guide" then
    Guide()
    return
  elseif cmd == "item" then
    local link = rest:match("|H(item:[^|]+)|h") and rest or nil
    if not link then ns.Print("usage: /eqt item <shift-click an item>") return end
    Explain(rest:match("(|c%x+|Hitem:.-|h.-|h|r)") or rest)
  elseif cmd == "spec" then
    ns.Print("scoring gear for " .. ns.ScoringLabel() .. (ns.db.spec == "auto" and " (spec from your talents)" or " (spec set in /eqt)"))
    -- what the talents say, tree by tree
    local pts, parts = ns.TalentPoints(), {}
    for i, p in ipairs(ns.PRESETS[ns.Class()] or {}) do parts[#parts + 1] = p[1] .. " " .. ((pts and pts[i]) or 0) end
    ns.Print("talent points: " .. (pts and table.concat(parts, ", ") or "the game didn't say (spec picked as before any talents)"))
  else
    local ok, e = pcall(ns.OpenOptions)
    if not ok then ns.Print("settings error: " .. tostring(e)) end
  end
end
