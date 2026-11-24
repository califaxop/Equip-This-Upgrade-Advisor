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
  local dpsBtn = UI.Button(panel, "Your " .. ns.Sim.Unit(), 110, function() ns.OpenDps() end)
  dpsBtn:SetPoint("LEFT", fb, "RIGHT", 8, 0)
  dpsBtn.tip = "Your damage (or healing) per second as Equip This! works it out, ability by ability, and what each stat is worth to it."
  track({ Refresh = function() if dpsBtn.SetLabel then dpsBtn.SetLabel("Your " .. ns.Sim.Unit()) end end })
  local hint = at(UI.Text(panel, "note", "/eqt item: how an item was scored.  /eqt guide: your spec's rotation.  /eqt dps: this window."), 26, yEnd - 30)

  panel:HookScript("OnShow", function() for _, w in ipairs(refreshers) do w.Refresh() end end)
  panel.height = -(yEnd - 66)
end

---------------------------------------------------------------------------
-- Your DPS / HPS window: the number, each ability's part, and what each stat is worth
---------------------------------------------------------------------------
local DPS_ROWS = 12
function ns.OpenDps()
  local win = EquipThisDpsWindow
  if not win then
    -- a pop-up like the others: solid, over the settings window (dimmed behind it), or mid-screen
    win = UI.Popup("EquipThisDpsWindow", 430, 130 + DPS_ROWS * 18 + 120)
    win.title = UI.Text(win, "title", "")
    win.title:SetPoint("TOPLEFT", 20, -18)
    win.total = UI.Text(win, "header", "")
    win.total:SetPoint("LEFT", win.title, "RIGHT", 12, 0)
    win.stats = UI.Text(win, "note", "")
    win.stats:SetPoint("TOPLEFT", 20, -44); win.stats:SetWidth(390)
    -- the table: ability, per cast, a minute, per second, share
    local cols = { { "Ability", 20, 150, "LEFT" }, { "Per hit", 170, 60, "RIGHT" }, { "A minute", 232, 56, "RIGHT" },
      { "Per sec", 290, 58, "RIGHT" }, { "Share", 350, 56, "RIGHT" } }
    for _, c in ipairs(cols) do
      local h = UI.Text(win, "note", c[1]); h:SetPoint("TOPLEFT", c[2], -68); h:SetWidth(c[3]); h:SetJustifyH(c[4])
    end
    win.rows = {}
    for i = 1, DPS_ROWS do
      local r = {}
      for j, c in ipairs(cols) do
        local fs = UI.Text(win, j == 1 and "line" or "value", "")
        fs:SetPoint("TOPLEFT", c[2], -68 - i * 18); fs:SetWidth(c[3]); fs:SetJustifyH(c[4]); fs:SetWordWrap(false)
        r[j] = fs
      end
      win.rows[i] = r
    end
    local wy = -68 - (DPS_ROWS + 1) * 18 - 6
    win.worthHead = UI.Section(win, "What stats are worth to it", 390)
    win.worthHead:SetPoint("TOPLEFT", 20, wy)
    win.worth = UI.Text(win, "line", "")
    win.worth:SetPoint("TOPLEFT", 20, wy - 32); win.worth:SetWidth(390); win.worth:SetSpacing(3)
    win.note = UI.Text(win, "note", "Per hit: an average hit, as your tooltip shows it (with your spell power). Per sec: with crits and misses. In grey: no spell of its own (procs, totems, pets), its part follows the site's sim.")
    win.note:SetPoint("BOTTOMLEFT", 20, 14); win.note:SetWidth(390)
    local function fmtN(x) return x >= 100 and format("%d", x + 0.5) or format("%.1f", x) end
    function win.Refresh()
      local d, why = ns.Sim.ReportData()
      win.title:SetText("Your " .. ns.Sim.Unit())
      for _, r in ipairs(win.rows) do for _, fs in ipairs(r) do fs:SetText("") end end
      if not d then win.total:SetText(""); win.stats:SetText(why or ""); win.worth:SetText(""); return end
      win.total:SetText(fmtN(d.total))
      win.stats:SetText(d.stats)
      for i, row in ipairs(d.rows) do
        local r = win.rows[i]
        if not r then break end
        r[1]:SetText(row[6] and ("|cff9d9d9d" .. row[1] .. "|r") or row[1])
        r[2]:SetText(row[2] and fmtN(row[2]) or "")
        r[3]:SetText(row[3] and format("%.1f", row[3]) or "")
        r[4]:SetText(fmtN(row[4]))
        r[5]:SetText(format("%d%%", row[5] * 100 + 0.5))
      end
      local lines = {}
      for i, w in ipairs(d.worth) do
        local cell = format("%s  |cff40ff40+%.2f%%|r", w[1], w[2])
        if i % 2 == 1 then lines[#lines + 1] = cell else lines[#lines] = lines[#lines] .. "        " .. cell end
      end
      win.worth:SetText(table.concat(lines, "\n"))
    end
    -- your numbers move with buffs and gear: keep it current while it's open
    local t = 0
    win:SetScript("OnUpdate", function(_, el) t = t + el; if t > 1 then t = 0; win.Refresh() end end)
    win:HookScript("OnShow", function() win.Refresh() end)
  end
  win.Refresh()
  win:Place(); win:Show()
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
