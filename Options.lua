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
  local weightRows = {}
  local now
  local function refreshWeights() for _, r in ipairs(weightRows) do r.Refresh() end end
  track(at(UI.Selector(panel, 300, opts, S("spec"), function() Changed(); refreshWeights(); if now then now.Refresh() end end,
    "Auto picks the talent tree you've put the most points in (before any talents: the one most players level in)."), 26, -84))
  now = at(UI.Text(panel, "note", ""), 26, -112)
  now.Refresh = function()
    local scale = ns.Scales.Active()
    now:SetText("Your spec: " .. ns.SpecName(ns.SpecKey()) .. (scale and ("  -  scoring with your scale \"" .. scale .. "\"") or ""))
  end
  track(now)

  -- Scale ----------------------------------------------------------------------
  -- your own named stat weights (theorycrafting), shared as Pawn-style strings
  at(UI.Section(panel, "Your scale", W_), 26, -140)
  local scaleOpts = {}
  local function fillScales()
    wipe(scaleOpts)
    scaleOpts[1] = { "", "Spec preset: " .. ns.SpecName(ns.SpecKey()) }
    for _, name in ipairs(ns.Scales.Names()) do scaleOpts[#scaleOpts + 1] = { name, name } end
  end
  fillScales()
  local scaleSel
  local function scalesChanged()
    fillScales(); Changed(); refreshWeights()
    if scaleSel then scaleSel.Refresh() end
    now.Refresh()
  end
  scaleSel = track(at(UI.Selector(panel, 300, scaleOpts,
    { function() return ns.db.scale or "" end, function(v) ns.db.scale = (v ~= "") and v or nil end },
    scalesChanged, "What gear is scored with: your spec's preset, or one of your own scales."), 26, -170))
  local sr = scaleSel.Refresh
  scaleSel.Refresh = function() fillScales(); sr() end
  local function bar(label, w, x, fn) local b = UI.Button(panel, label, w, fn); b:SetPoint("TOPLEFT", x, -200); return b end
  bar("New", 70, 26, function()
    UI.Prompt("EquipThisPrompt", "New scale", "Starts from the weights in use now. Name it:", "My scale", function(text)
      local name = ns.Scales.Create(text, ns.CurrentWeights())
      ns.Print("made scale \"" .. name .. "\". Tune it under Stat weights.")
      scalesChanged()
    end)
  end)
  bar("Rename", 80, 102, function()
    local old = ns.Scales.Active()
    if not old then ns.Print("the spec preset can't be renamed: pick one of your scales first.") return end
    UI.Prompt("EquipThisPrompt", "Rename scale", "New name for \"" .. old .. "\":", old, function(text)
      local name = ns.Scales.Rename(old, text)
      if name and name ~= old then ns.Print("renamed scale \"" .. old .. "\" to \"" .. name .. "\".") end
      scalesChanged()
    end)
  end)
  bar("Import", 80, 188, function()
    UI.Prompt("EquipThisPrompt", "Import a scale", "Paste a Pawn-style scale string: ( Pawn: v1: \"Name\": Strength=1, ... )", "", function(text)
      local name, weights, ignored = ns.Scales.Parse(text)
      if not name then ns.Print("couldn't import: " .. tostring(weights) .. "."); return end
      name = ns.Scales.Create(name, weights)
      ns.Print("imported scale \"" .. name .. "\"" .. ((ignored and #ignored > 0) and (" (skipped stats it doesn't use: " .. table.concat(ignored, ", ") .. ")") or "") .. ".")
      scalesChanged()
    end)
  end)
  bar("Export", 80, 274, function()
    local name = ns.Scales.Active() or ns.SpecName(ns.SpecKey())
    UI.ShowLink("EquipThisLinkWindow", "Export: " .. name, ns.Scales.Export(name, ns.CurrentWeights()))
  end)
  bar("Delete", 80, 360, function()
    local name = ns.Scales.Active()
    if not name then ns.Print("the spec preset can't be deleted: pick one of your scales first.") return end
    UI.Confirm("EquipThisConfirm", "Are you sure you want to delete this preset?\n|cffffd200" .. name .. "|r", function()
      ns.Scales.Delete(name); ns.Print("deleted scale \"" .. name .. "\".")
      scalesChanged()
    end)
  end)
  local sn = at(UI.Text(panel, "note", "Import Pawn-style strings from theorycrafting guides (turned into 0-5), or export yours to share."), 26, -228)
  sn:SetWidth(W_)

  -- Show ---------------------------------------------------------------------
  at(UI.Section(panel, "Show", W_), 26, -256)
  track(at(UI.Check(panel, "Upgrade or downgrade on item tooltips", S("tooltip"), W_, Changed), 26, -286))
  track(at(UI.Check(panel, "Glow the best quest reward", S("rewards"), W_, Changed), 26, -310))
  track(at(UI.Check(panel, "No upgrade among the rewards: mark the one that sells for most", S("sellFallback"), W_, Changed), 26, -334))

  -- Weights ------------------------------------------------------------------
  at(UI.Section(panel, "Stat weights", W_), 26, -370)
  local n = at(UI.Text(panel, "note", "How much each stat matters to you: 0 (ignore) to 5 (most). Decimals OK, e.g. 3.5. Hover a stat to see what its weight is worth."), 26, -398)
  n:SetWidth(W_)
  local y0 = -434
  for i, key in ipairs(ns.STAT_ORDER) do
    local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
    local x, y = 26 + col * 240, y0 - row * 26
    at(UI.Text(panel, "line", ns.STAT_NAMES[key]), x, y - 3)
    -- hover the stat for what its weight is worth
    local function tip(owner)
      GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
      GameTooltip:SetText(ns.STAT_NAMES[key], 1, 1, 1)
      for _, line in ipairs(ns.WeightInfo(key, ns.CurrentWeights())) do GameTooltip:AddLine(line, 0.85, 0.85, 0.85, true) end
      GameTooltip:Show()
    end
    local hover = CreateFrame("Frame", nil, panel)
    hover:SetSize(155, 20); hover:SetPoint("TOPLEFT", x - 2, y + 1)
    hover:EnableMouse(true)
    hover:SetScript("OnEnter", tip)
    hover:SetScript("OnLeave", function() GameTooltip:Hide() end)
    local e = UI.Edit(panel, 56, {
      function() local w = ns.CurrentWeights(); return w[key] and tostring(w[key]) or "0" end,
      function(v)
        local num = tonumber(v)
        if not num then return end
        num = math.max(0, math.min(5, math.floor(num * 100 + 0.5) / 100)) -- 0 to 5
        local name, scale = ns.Scales.Active()
        if scale then
          scale[key] = num -- your own scale
        else
          local k = ns.SpecKey() -- the spec preset, with your edits
          ns.db.weights[k] = ns.db.weights[k] or {}
          ns.db.weights[k][key] = num
        end
        Changed()
      end }, "0", false, true)
    e:SetPoint("TOPLEFT", x + 160, y)
    e:HookScript("OnEnter", tip)
    e:HookScript("OnLeave", function() GameTooltip:Hide() end)
    weightRows[#weightRows + 1] = e
    track(e)
  end
  local yEnd = y0 - math.ceil(#ns.STAT_ORDER / 2) * 26 - 10
  local reset = at(UI.Button(panel, "Reset weights", 130, function()
    local name = ns.Scales.Active()
    if name then
      ns.db.scales[name] = ns.Weights() -- your scale back to the spec preset's numbers
      if ns.db.scaleSkills then ns.db.scaleSkills[name] = nil end
    else
      ns.db.weights[ns.SpecKey()] = nil
      if ns.db.skills then ns.db.skills[ns.SpecKey()] = nil end
    end
    Changed(); refreshWeights()
  end), 26, yEnd)
  local fb = UI.Button(panel, "Report a bug / suggest", 170, function()
    UI.ShowLink("EquipThisLinkWindow", "Equip This!: bugs and ideas", "https://github.com/califaxop/Equip-This-Upgrade-Advisor/issues/new/choose")
  end)
  -- your skills (for item effects on them) in their own box
  local skillsBtn = UI.Button(panel, "Skills", 90, function() ns.OpenSkills(refreshWeights) end)
  skillsBtn:SetPoint("LEFT", reset, "RIGHT", 8, 0)
  skillsBtn.tip = "The skills you use, 0 to 5 each: items that improve one count by its weight."
  fb:SetPoint("LEFT", skillsBtn, "RIGHT", 8, 0)
  local hint = at(UI.Text(panel, "note", "/eqt item: how an item was scored"), 26, yEnd - 30)

  panel:HookScript("OnShow", function() for _, w in ipairs(refreshers) do w.Refresh() end end)
  panel.height = -(yEnd - 66)
end

---------------------------------------------------------------------------
-- Skills box: the list in use (spec or scale), one row per skill, + to add one
---------------------------------------------------------------------------
local SKILL_ROWS = 10 -- rows shown before it scrolls
function ns.OpenSkills(onChange)
  local win = EquipThisSkills
  if not win then
    win = UI.Popup("EquipThisSkills", 420, 200)
    local title = UI.Text(win, "title", "Skills")
    title:SetPoint("TOPLEFT", 20, -18)
    win.sub = UI.Text(win, "note", "")
    win.sub:SetPoint("LEFT", title, "RIGHT", 10, 0)
    local note = UI.Text(win, "note", "The skills you use, 0 to 5 each. Items that improve one (\"+10% Stormstrike damage\", \"+1% crit chance of Healing Wave\") count by its weight. Unlisted skills count for nothing. Type a name or drag a spell in.")
    note:SetPoint("TOPLEFT", 20, -44); note:SetWidth(380)
    local hs = UI.Text(win, "note", "Skill"); hs:SetPoint("TOPLEFT", 22, -100)
    local hw = UI.Text(win, "note", "Weight"); hw:SetPoint("TOPLEFT", 294, -100)
    win.scroll, win.content = UI.Scroll(win, 390, 26)
    win.scroll:SetPoint("TOPLEFT", 20, -118)
    win.rows = {}
    local function changed()
      ns.Score.ClearCache()
      if ns.Display then pcall(ns.Display.MarkRewards) end
      if win.onChange then win.onChange() end
    end
    local function row(i)
      local r = win.rows[i]
      if r then return r end
      r = {}
      local function skill() return ns.CurrentSkills()[i] end
      local function tip(owner)
        local s = skill()
        GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
        GameTooltip:SetText(s and s[1] or "New skill", 1, 1, 1)
        for _, line in ipairs(ns.SkillInfo(s and s[1] or "", s and tonumber(s[2]))) do GameTooltip:AddLine(line, 0.85, 0.85, 0.85, true) end
        GameTooltip:Show()
      end
      r.name = UI.Edit(win.content, 266, {
        function() local s = skill(); return s and s[1] or "" end,
        function(v)
          local before = #ns.CurrentSkills()
          ns.SetSkill(i, v, (i > before) and r.pending or nil) -- (a weight typed before the name)
          r.pending = nil
          if i > before and #ns.CurrentSkills() > before then win.blank = math.max(0, win.blank - 1) end
          changed(); win.Layout()
        end }, "Skill name, or drag a spell here", true)
      r.name:SetPoint("TOPLEFT", 0, -(i - 1) * 26)
      r.weight = UI.Edit(win.content, 56, {
        function() local s = skill(); return s and tostring(s[2]) or tostring(r.pending or 3) end,
        function(v)
          local num = tonumber(v)
          if not num then return end
          num = math.max(0, math.min(5, math.floor(num * 100 + 0.5) / 100))
          if not skill() then r.pending = num; return end
          ns.SetSkill(i, nil, num)
          changed()
        end }, "", false, true)
      r.weight:SetPoint("TOPLEFT", 274, -(i - 1) * 26)
      r.remove = UI.Button(win.content, "\195\151", 24, function()
        if skill() then ns.RemoveSkill(i); changed() else win.blank = math.max(0, win.blank - 1) end
        win.Layout()
      end)
      r.remove:SetPoint("TOPLEFT", 338, -(i - 1) * 26 + 1)
      r.remove.tip = "Remove"
      for _, e in ipairs({ r.name, r.weight }) do
        e:HookScript("OnEnter", tip)
        e:HookScript("OnLeave", function() GameTooltip:Hide() end)
      end
      win.rows[i] = r
      return r
    end
    win.add = UI.Button(win, "+ Add skill", 110, function()
      win.blank = win.blank + 1
      win.Layout()
      local r = win.rows[#ns.CurrentSkills() + win.blank]
      if r then r.name:SetFocus() end
      win.scroll:SetVerticalScroll(math.max(0, win.content:GetHeight() - win.scroll:GetHeight())); win.scroll.Update()
    end)
    local reset = UI.Button(win, "Reset to suggested", 150, function()
      ns.ResetSkills(); win.blank = 0; changed(); win.Layout()
    end)
    reset:SetPoint("LEFT", win.add, "RIGHT", 8, 0)
    reset.tip = "Back to the suggested list for your spec."
    local done = UI.Button(win, "Done", 80, function() win:Hide() end)
    done:SetPoint("LEFT", reset, "RIGHT", 8, 0)
    function win.Layout()
      local n = #ns.CurrentSkills() + win.blank
      for i = 1, n do
        local r = row(i)
        for k, w in pairs(r) do if k ~= "pending" then w:Show() end end
        r.name.Refresh(); r.weight.Refresh()
      end
      for i = n + 1, #win.rows do
        win.rows[i].pending = nil
        for k, w in pairs(win.rows[i]) do if k ~= "pending" then w:Hide() end end
      end
      local shown = math.max(1, math.min(n, SKILL_ROWS))
      win.content:SetHeight(math.max(1, n * 26))
      win.scroll:SetHeight(shown * 26)
      win.scroll.Update()
      win.add:ClearAllPoints(); win.add:SetPoint("TOPLEFT", 20, -118 - shown * 26 - 10)
      win:SetHeight(118 + shown * 26 + 10 + 22 + 20)
      local scale = ns.Scales.Active()
      win.sub:SetText(scale and ("scale: " .. scale) or ns.SpecName(ns.SpecKey()))
    end
  end
  win.onChange = onChange
  win.blank = (#ns.CurrentSkills() == 0) and 1 or 0
  win.scroll:SetVerticalScroll(0)
  win.Layout()
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
