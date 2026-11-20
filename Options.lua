-- Settings window (/gsight), in the same style as the other addons.
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

  local title = at(UI.Text(panel, "title", "Gearsight"), 26, -20)
  UI.Text(panel, "note", "Which gear is better for you."):SetPoint("LEFT", title, "RIGHT", 10, -1)

  -- Spec ---------------------------------------------------------------------
  at(UI.Section(panel, "Your spec", W_), 26, -54)
  local class = ns.Class()
  local opts = { { "auto", "Auto: from my talents" } }
  for i, p in ipairs(ns.PRESETS[class] or {}) do opts[#opts + 1] = { class .. ":" .. i, p[1] } end
  local weightRows = {}
  local function refreshWeights() for _, r in ipairs(weightRows) do r.Refresh() end end
  track(at(UI.Selector(panel, 300, opts, S("spec"), function() Changed(); refreshWeights() end,
    "Auto picks the talent tree you've put the most points in (before any talents: the one most players level in)."), 26, -84))
  local now = at(UI.Text(panel, "note", ""), 26, -112)
  now.Refresh = function() now:SetText("Scoring gear for: " .. ns.SpecName(ns.SpecKey())) end
  track(now)

  -- Show ---------------------------------------------------------------------
  at(UI.Section(panel, "Show", W_), 26, -140)
  track(at(UI.Check(panel, "Upgrade or downgrade on item tooltips", S("tooltip"), W_, Changed), 26, -170))
  track(at(UI.Check(panel, "Glow the best quest reward", S("rewards"), W_, Changed), 26, -194))
  track(at(UI.Check(panel, "No upgrade among the rewards: mark the one that sells for most", S("sellFallback"), W_, Changed), 26, -218))

  -- Weights ------------------------------------------------------------------
  at(UI.Section(panel, "Stat weights", W_), 26, -254)
  local n = at(UI.Text(panel, "note", "How much each stat is worth to your spec, the main stat being 1. Crit and hit are per 1%; weapon DPS only counts on weapons. 0 = ignore."), 26, -282)
  n:SetWidth(W_)
  local y0 = -318
  for i, key in ipairs(ns.STAT_ORDER) do
    local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
    local x, y = 26 + col * 240, y0 - row * 26
    at(UI.Text(panel, "line", ns.STAT_NAMES[key]), x, y - 3)
    local e = UI.Edit(panel, 56, {
      function() local w = ns.Weights(); return w[key] and tostring(w[key]) or "0" end,
      function(v)
        local num = tonumber(v)
        if not num then return end
        local k = ns.SpecKey()
        ns.db.weights[k] = ns.db.weights[k] or {}
        ns.db.weights[k][key] = num
        Changed()
      end }, "0", false, true)
    e:SetPoint("TOPLEFT", x + 160, y)
    weightRows[#weightRows + 1] = e
    track(e)
  end
  local yEnd = y0 - math.ceil(#ns.STAT_ORDER / 2) * 26 - 10
  local reset = at(UI.Button(panel, "Reset weights", 130, function()
    ns.db.weights[ns.SpecKey()] = nil; Changed(); refreshWeights()
  end), 26, yEnd)
  local fb = UI.Button(panel, "Report a bug / suggest", 170, function()
    UI.ShowLink("GearsightLinkWindow", "Gearsight: bugs and ideas", "https://github.com/califaxop/gearsight/issues/new/choose")
  end)
  fb:SetPoint("LEFT", reset, "RIGHT", 8, 0)
  local hint = UI.Text(panel, "note", "/gsight item: how scored")
  hint:SetPoint("LEFT", fb, "RIGHT", 10, 0)

  panel:HookScript("OnShow", function() for _, w in ipairs(refreshers) do w.Refresh() end end)
  panel.height = -(yEnd - 46)
end

function ns.CreateOptions()
  local p = CreateFrame("Frame"); p.name = "Gearsight"
  pcall(function()
    local t = p:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    t:SetPoint("TOPLEFT", 16, -16); t:SetText("Gearsight")
    local b = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    b:SetSize(200, 24); b:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, -12); b:SetText("Open Gearsight settings")
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
    window = UI.Window("GearsightOptionsWindow", 522, 640)
    window:SetPoint("CENTER")
    local ok, e = pcall(BuildPanel, window)
    if not ok then window:Hide(); window = nil; ns.Print("settings failed: " .. tostring(e)); return end
    window:SetHeight(window.height or 640)
    window:Hide()
  end
  UI.Restyle()
  window:SetScale(math.max(0.5, math.min(1, (UIParent:GetHeight() - 40) / window:GetHeight())))
  window:SetShown(not window:IsShown())
end
