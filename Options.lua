-- Settings window (/eqt), in the same style as the other addons.
local _, ns = ...
local UI = ns.UI
local W_ = 470 -- content width
local window

local function Changed()
  ns.Score.ClearCache()
  if ns.Display then pcall(ns.Display.MarkRewards) end
end
local function S(key) return { function() return ns.db[key] end, function(v) ns.db[key] = v end } end

local function BuildPanel(panel)
  local refreshers = {}
  local function track(w) refreshers[#refreshers + 1] = w; return w end
  local function at(w, x, y) w:SetPoint("TOPLEFT", x, y); return w end

  local title = at(UI.Text(panel, "title", "Equip This!"), 26, -20)
  UI.Text(panel, "note", "Which gear is better for you."):SetPoint("LEFT", title, "RIGHT", 10, -1)

  -- Spec ---------------------------------------------------------------------
  at(UI.Section(panel, "Your spec", W_), 26, -54)
  local class = ns.Class()
  local opts = { { "auto", "Auto: from my talents" } }
  for i, p in ipairs(ns.PRESETS[class] or {}) do opts[#opts + 1] = { class .. ":" .. i, p[1] } end
  local rows = {}
  local function refreshRows() for _, r in ipairs(rows) do r.Refresh() end end
  local now
  track(at(UI.Selector(panel, 300, opts, S("spec"), function() Changed(); refreshRows(); if now then now.Refresh() end end,
    "Auto picks the talent tree you've put the most points in (before any talents: the one most players level in)."), 26, -84))
  now = at(UI.Text(panel, "note", ""), 26, -112)
  now.Refresh = function() now:SetText("Scoring gear for: " .. ns.ScoringLabel()) end
  track(now)

  -- Show ---------------------------------------------------------------------
  at(UI.Section(panel, "Show", W_), 26, -140)
  track(at(UI.Check(panel, "Upgrade or downgrade on item tooltips", S("tooltip"), W_, Changed), 26, -170))
  track(at(UI.Check(panel, "Glow the best quest reward", S("rewards"), W_, Changed), 26, -194))
  track(at(UI.Check(panel, "No upgrade among the rewards: mark the one that sells for most", S("sellFallback"), W_, Changed), 26, -218))
  local armor = track(at(UI.Check(panel, "From level 40, only my best armor type (mail or plate) can be an upgrade", S("bestArmorOnly"), W_, Changed), 26, -242))
  armor.tip = "Shamans and hunters: mail; warriors and paladins: plate. Off by default: Forever has no armor specialization, so a lighter piece with better stats really is better."

  -- Priorities ---------------------------------------------------------------
  at(UI.Section(panel, "Your priorities", W_), 26, -278)
  local n = at(UI.Text(panel, "note", "What you want more of. Pick a goal (Auto: Leveling until the level cap, then Damage), then change any stat on top of it. Hover a stat for what it's worth."), 26, -306)
  n:SetWidth(W_)
  local function changed() Changed(); refreshRows(); now.Refresh() end
  -- the goal: the base; your stat changes sit on top of it
  at(UI.Text(panel, "line", "Goal"), 26, -345)
  local goalOpts = {}
  for _, g in ipairs(ns.Goals()) do goalOpts[#goalOpts + 1] = { g[1], g[2] } end
  local goalTip = {}
  for _, g in ipairs(ns.Goals()) do goalTip[#goalTip + 1] = g[2] .. ": " .. g[3] end
  goalTip[#goalTip + 1] = "Your stat changes below stay on top of whichever goal you pick."
  local goal = at(UI.Selector(panel, 220, goalOpts,
    { function() return ns.Priorities().goal or "auto" end, function(v) ns.SetGoal(v) end }, changed,
    table.concat(goalTip, "\n")), 106, -342)
  rows[#rows + 1] = goal; track(goal)
  -- each stat: Default (the goal's) / Ignore / Normal / Higher / Highest
  local y0 = -378
  for i, key in ipairs(ns.STAT_ORDER) do
    local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
    local x, y = 26 + col * 240, y0 - row * 26
    local lbl = at(UI.Text(panel, "line", ns.STAT_NAMES[key]), x, y - 3)
    lbl:SetWidth(108); lbl:SetJustifyH("LEFT"); if lbl.SetWordWrap then lbl:SetWordWrap(false) end
    local function tip(owner)
      GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
      GameTooltip:SetText(ns.STAT_NAMES[key], 1, 1, 1)
      for j, line in ipairs(ns.PriorityInfo(key)) do
        if j > 1 then GameTooltip:AddLine(" ") end -- (a gap between the parts: easier to read)
        GameTooltip:AddLine(line, 0.85, 0.85, 0.85, true)
      end
      GameTooltip:Show()
    end
    local hover = CreateFrame("Frame", nil, panel)
    hover:SetSize(110, 20); hover:SetPoint("TOPLEFT", x - 2, y + 1)
    hover:EnableMouse(true)
    hover:SetScript("OnEnter", tip)
    hover:SetScript("OnLeave", function() GameTooltip:Hide() end)
    local sel = UI.Selector(panel, 120, ns.LEVELS,
      { function() return ns.Level(key) end, function(v) ns.SetLevel(key, v) end }, changed)
    sel:SetPoint("TOPLEFT", x + 112, y + 2)
    if sel.HookScript then sel:HookScript("OnEnter", tip); sel:HookScript("OnLeave", function() GameTooltip:Hide() end) end
    rows[#rows + 1] = sel; track(sel)
  end
  local yEnd = y0 - math.ceil(#ns.STAT_ORDER / 2) * 26 - 10
  local reset = at(UI.Button(panel, "Reset priorities", 130, function() ns.ResetPriorities(); changed() end), 26, yEnd)
  reset.tip = "Back to Auto, with none of your own stat changes."
  local fb = UI.Button(panel, "Report a bug / suggest", 170, function()
    UI.ShowLink("EquipThisLinkWindow", "Equip This!: bugs and ideas", "https://github.com/califaxop/Equip-This-Upgrade-Advisor/issues/new/choose")
  end)
  fb:SetPoint("LEFT", reset, "RIGHT", 8, 0)
  local hint = at(UI.Text(panel, "note", "/eqt item: how an item was scored.  /eqt guide: your spec's rotation."), 26, yEnd - 30)

  panel:HookScript("OnShow", function() for _, w in ipairs(refreshers) do w.Refresh() end end)
  panel.height = -(yEnd - 66)
end

function ns.CreateOptions()
  local p = CreateFrame("Frame"); p.name = "Equip This!"
  pcall(function()
    local t = p:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    t:SetPoint("TOPLEFT", 16, -16); t:SetText("Equip This!")
    local b = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    b:SetSize(200, 24); b:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, -12); b:SetText("Open Equip This! settings")
    b:SetScript("OnClick", function()
      if SettingsPanel and SettingsPanel.Close then pcall(SettingsPanel.Close, SettingsPanel, true) end
      if not (window and window:IsShown()) then ns.OpenOptions() end
    end)
    if Settings and Settings.RegisterCanvasLayoutCategory then
      Settings.RegisterAddOnCategory(Settings.RegisterCanvasLayoutCategory(p, p.name))
    elseif InterfaceOptions_AddCategory then
      InterfaceOptions_AddCategory(p)
    end
  end)
end

function ns.OpenOptions()
  if not window then
    window = UI.Window("EquipThisOptionsWindow", 522, 640)
    window:SetPoint("CENTER")
    UI.SetHost(window) -- pop-ups (New, Rename, Import, Delete...) sit over this window
    local ok, e = pcall(BuildPanel, window)
    if not ok then window:Hide(); window = nil; ns.Print("settings failed: " .. tostring(e)); return end
    window:SetHeight(window.height or 640)
    window:Hide()
  end
  UI.Restyle()
  window:SetScale(math.max(0.5, math.min(1, (UIParent:GetHeight() - 40) / window:GetHeight())))
  window:SetShown(not window:IsShown())
end
