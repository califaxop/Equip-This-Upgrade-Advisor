-- Settings window (/eqt), in the same style as the other addons.
local _, ns = ...
local UI = ns.UI
local W_ = 690 -- content width
local window

local function Changed()
  ns.Bridge.Sync()
  if ns.Display then pcall(ns.Display.MarkRewards) end
end
local function S(key) return { function() return ns.db[key] end, function(v) ns.db[key] = v end } end
-- a setting of the engine's own (kept in its saved data)
local function E(key) return { function() return ns.Engine.db and ns.Engine.db[key] end, function(v) if ns.Engine.db then ns.Engine.db[key] = v end end } end

-- The fight records export (like Questie's trace export): a link to the form, the line to copy,
-- what's in it, and "I reported this" (the next export holds only what's new).
-- (the form's version field filled in: Equip This!'s own version)
local function AddonVersion()
  local get = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
  local ok, v = pcall(get, "EquipThis", "Version")
  return ok and type(v) == "string" and v or nil
end
local SUBMIT_URL = "https://github.com/califaxop/Equip-This-Upgrade-Advisor/issues/new?template=fight_records.yml"
  .. ((AddonVersion() and ("&version=" .. AddonVersion())) or "")
local INCLUDED = "Included: your class, spec and level, how long each fight lasted, your damage and healing per spell, and Equip This!'s own estimate. Never: your name, realm, guild, other players or any IDs."
local function hms(s)
  s = math.floor(s or 0)
  local h, m = math.floor(s / 3600), math.floor((s % 3600) / 60)
  if h > 0 then return format("%d Hr %d Min", h, m) end
  return format("%d Min %d Sec", m, s % 60)
end
local exportWin
function ns.ShowReport()
  local FR = ns.Engine.FightRecorder
  local w = exportWin
  if not w then
    w = UI.Popup("EquipThisExportWindow", 640, 392)
    exportWin = w
    local title = UI.Text(w, "title", "Equip This! Fight Records")
    title:SetPoint("TOP", 0, -16)
    w.url = UI.Edit(w, 580, { function() return SUBMIT_URL end, function() end })
    w.url:SetPoint("TOP", 0, -44)
    w.url:HookScript("OnTextChanged", function(self, user) if user and self:GetText() ~= SUBMIT_URL then self:SetText(SUBMIT_URL); self:HighlightText() end end)
    w.url:HookScript("OnEditFocusGained", function(self) self:HighlightText() end)
    local note = UI.Text(w, "note", "Copy the line below and paste it into the form at the link above (needs a GitHub account), or into a comment on Equip This!'s CurseForge page. "
      .. "Please send it again now and then: each export only holds what's been recorded since the last one you sent. It helps the classes and specs the author can't play.")
    note:SetPoint("TOP", 0, -74); note:SetWidth(580); note:SetJustifyH("CENTER")
    w.line = UI.Edit(w, 580, { function() return w.text or "" end, function() end })
    w.line:SetPoint("TOP", 0, -134)
    w.line:HookScript("OnTextChanged", function(self, user) if user and self:GetText() ~= w.text then self:SetText(w.text or ""); self:HighlightText() end end)
    w.line:HookScript("OnEditFocusGained", function(self) self:HighlightText() end)
    -- what's in it (counters), two columns
    w.stats = {}
    local ICONS = { "Interface\\Icons\\Ability_DualWield", "Interface\\Icons\\INV_Misc_PocketWatch_01", "Interface\\Icons\\INV_Misc_Book_09",
      "Interface\\Icons\\Spell_Nature_LightningShield", "Interface\\Icons\\INV_Misc_Note_01", "Interface\\Icons\\Achievement_Level_10" }
    for i = 1, 6 do
      local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
      local icon = w:CreateTexture(nil, "ARTWORK")
      icon:SetTexture(ICONS[i]); icon:SetSize(18, 18)
      icon:SetPoint("TOPLEFT", 40 + col * 300, -172 - row * 26)
      local t = UI.Text(w, "line", "")
      t:SetPoint("LEFT", icon, "RIGHT", 8, 0)
      w.stats[i] = t
    end
    local inc = UI.Text(w, "note", INCLUDED)
    inc:SetPoint("TOP", 0, -258); inc:SetWidth(580); inc:SetJustifyH("CENTER")
    local inside = UI.Button(w, "What's inside", 130, function()
      local text = FR.ReportText()
      -- (in the export window's place; closing it brings the export window back)
      w:Hide()
      UI.ShowText("EquipThisInsideWindow", "What's inside, fight by fight", INCLUDED, text, function() ns.ShowReport() end)
    end)
    inside:SetPoint("BOTTOMLEFT", 20, 16)
    inside.tip = "The same records, one fight a line, in plain words."
    w.done = UI.Button(w, "I reported this", 150, function()
      local n = FR.MarkReported()
      ns.Print(format("thank you! %d fight record(s) marked as sent; the next export holds only new ones.", n))
      ns.ShowReport()
    end)
    w.done:SetPoint("BOTTOM", 60, 16)
    w.done.tip = "Once you've sent it: the next export holds only fights recorded after now."
    local close = UI.Button(w, "Close", 110, function() w:Hide() end)
    close:SetPoint("BOTTOMRIGHT", -20, 16)
  end
  local line, n = FR.ExportString()
  local sum = FR.Summary()
  local share = ns.Engine.db and ns.Engine.db.share
  w.text = n > 0 and line or (share and "(no fights recorded since your last export: play a few and come back)"
    or "(nothing recorded: tick \"Help improve Equip This!\" in /eqt to start)")
  w.url:SetText(SUBMIT_URL)   -- (set on every open: the box only fills itself when it loses focus)
  if w.url.SetCursorPosition then w.url:SetCursorPosition(0) end
  w.line:SetText(w.text)
  local G = "|cffffd200"
  local specs = #sum.specs > 0 and (sum.specs[1] .. (#sum.specs > 1 and format(" +%d more", #sum.specs - 1) or "")) or "-"
  w.stats[1]:SetText("Fights recorded: " .. G .. sum.fights .. "|r")
  w.stats[2]:SetText("Time in combat: " .. G .. hms(sum.seconds) .. "|r")
  w.stats[3]:SetText("Spells tracked: " .. G .. sum.spells .. "|r")
  w.stats[4]:SetText("Specs: " .. G .. specs .. "|r")
  w.stats[5]:SetText("Sent before: " .. G .. sum.sentBefore .. " fights|r")
  w.stats[6]:SetText("Levels: " .. G .. (sum.levels and (sum.levels[1] == sum.levels[2] and sum.levels[1] or (sum.levels[1] .. "-" .. sum.levels[2])) or "-") .. "|r")
  if w.done.SetEnabled then w.done:SetEnabled(n > 0) end
  w:Place(); w:Show()
  w.line:SetFocus(); w.line:HighlightText()
end

-- the reminder in chat (twice a week at most: after Wednesday's maintenance and on Sunday, with 25+ new records; the engine decides when)
function ns.RemindToShare(n)
  ns.Print(format("You have %d new fight records to share (optional). Each export only covers what's been recorded so far, so please share again now and then. "
    .. "|cff40ff40|Haddon:EquipThis:records|h[Click here to open the export window]|h|r", n))
end

local function BuildPanel(panel)
  local B = ns.Bridge
  local refreshers = {}
  local function track(w) refreshers[#refreshers + 1] = w; return w end
  local function at(w, x, y) w:SetPoint("TOPLEFT", x, y); return w end

  local title = at(UI.Text(panel, "title", "Equip This!"), 26, -20)
  UI.Text(panel, "note", "Which gear is better for you."):SetPoint("LEFT", title, "RIGHT", 10, -1)

  -- Spec ---------------------------------------------------------------------
  at(UI.Section(panel, "Your spec", W_), 26, -54)
  local opts = { { "auto", "Auto: from my talents" } }
  for _, t in ipairs(B.TREES[ns.Class()] or {}) do opts[#opts + 1] = { t, t } end
  local rows = {}
  local function refreshRows() for _, r in ipairs(rows) do r.Refresh() end end
  local now
  track(at(UI.Selector(panel, 300, opts, S("spec"), function() Changed(); refreshRows(); if now then now.Refresh() end end,
    "Auto uses the talent tree you've put the most points in."), 26, -84))
  now = at(UI.Text(panel, "note", ""), 26, -112)
  now.Refresh = function() now:SetText("Comparing gear for: " .. B.ScoringLabel()) end
  track(now)

  -- Show ---------------------------------------------------------------------
  at(UI.Section(panel, "Show", W_), 26, -140)
  track(at(UI.Check(panel, "Upgrade or downgrade on item tooltips", S("tooltip"), W_, Changed), 26, -170))
  track(at(UI.Check(panel, "Glow the best quest reward", S("rewards"), W_, Changed), 26, -194))
  track(at(UI.Check(panel, "No upgrade among the rewards: mark the one that sells for most", S("sellFallback"), W_, Changed), 26, -218))
  local armor = track(at(UI.Check(panel, "From level 40, only my best armor type (mail or plate) can be an upgrade", S("bestArmorOnly"), W_, Changed), 26, -242))
  armor.tip = "Shamans and hunters: mail; warriors and paladins: plate. Off by default: Forever has no armor specialization, so a lighter piece with better stats really is better."
  local pvp = track(at(UI.Check(panel, "PvP numbers on tooltips too (burst, sustained damage, survival vs players)", S("pvp"), W_, Changed), 26, -266))
  pvp.tip = "Against a player of your level armored like you: no glancing blows, half the damage you take is magic. Separate from the PvE numbers."

  -- Your build ---------------------------------------------------------------
  at(UI.Section(panel, "Your build", W_), 26, -302)
  local n = at(UI.Text(panel, "note", "Each item is worked out on your own character: your stats, talents, abilities, weapon imbue and procs, and how you really fight. Damage (or healing, or threat for tanks) and survivability are shown apart; the slider says how they weigh in the Upgrade / Downgrade verdict."), 26, -330)
  n:SetWidth(W_)
  local function changed() Changed(); refreshRows(); now.Refresh() end
  at(UI.Text(panel, "line", "Build"), 26, -375)
  local buildOpts, buildTip = {}, {}
  for _, b in ipairs(B.BUILDS) do
    buildOpts[#buildOpts + 1] = { b[1], B.BuildName(b[1]) }
    buildTip[#buildTip + 1] = B.BuildName(b[1]) .. ": " .. b[5]
  end
  local build = at(UI.Selector(panel, 230, buildOpts,
    { function() local c = ns.db.builds and ns.db.builds[B.SpecKey()]; return c and c.build or "auto" end, function(v) B.SetBuild(v) end }, changed,
    table.concat(buildTip, "\n") .. "\nMoving the slider makes it your own mix."), 86, -372)
  rows[#rows + 1] = build; track(build)
  local function leftEnd() local _, u = B.MainMetric(); return u == "HPS" and "More Healing" or (u == "Threat" and "More Threat" or "More Damage") end
  local mix = UI.Slider(panel, "", W_, 0, 1, 0.05, { function() return B.Mix() end, function(v) B.SetMix(v) end },
    function() return "More Survivability" end, changed)
  mix:SetPoint("TOPLEFT", 26, -410)
  rows[#rows + 1] = mix; track(mix)
  local leftLbl = at(UI.Text(panel, "value", ""), 26, -410)
  local mixText = UI.Text(panel, "note", "")
  mixText:SetPoint("TOP", mix, "BOTTOM", 0, -2)
  local mixRefresh = track({ Refresh = function()
    leftLbl:SetText(leftEnd())
    local t = B.Mix()
    mixText:SetText(format("%d%% %s  /  %d%% survivability", (1 - t) * 100 + 0.5, leftEnd():gsub("^More ", ""):lower(), t * 100 + 0.5))
  end })
  rows[#rows + 1] = mixRefresh
  local tank = at(UI.Check(panel, "I tank: score threat and survivability as a tank",
    { function() return B.IsTank() end, function(v) B.SetTank(v) end }, W_, changed), 26, -464)
  tank.tip = "Threat (your damage times your stance, form or aura's threat, from Forever's own data) takes damage's place, and survivability counts as a tank's. Protection always tanks; a Defensive Stance, Bear Form or Righteous Fury does too."
  rows[#rows + 1] = { Refresh = function() tank.Refresh(); if tank.SetActive then tank.SetActive(not B.IsTankSpec()) end end }
  track(rows[#rows])
  at(UI.Text(panel, "line", "Raid at 60"), 26, -499)
  local raidOpts = {}
  for _, k in ipairs(B.RAID_ORDER) do raidOpts[#raidOpts + 1] = { k, B.RAIDS[k].name } end
  local raid = at(UI.Selector(panel, 260, raidOpts, { function() return B.Raid() end, function(v) B.SetRaid(v) end }, changed,
    "At the level cap, survivability counts how much of what hits you in the raid you're gearing for is magic. Measured on Warcraft Logs from WoW Classic (Era) raids, not Forever's own: Forever's versions of these raids may hit differently. Kept per character. While leveling, a fifth (assumed)."), 120, -496)
  local raidNote = at(UI.Text(panel, "note", ""), 390, -499)
  local function raidRefresh()
    raid.Refresh()
    local r = B.RAIDS[B.Raid()]
    raidNote:SetText(format("%d%% of what hits %s is magic", (B.IsTank() and r.tank or r.other) * 100 + 0.5, B.IsTank() and "a tank" or "you"))
  end
  track({ Refresh = raidRefresh }); rows[#rows + 1] = { Refresh = raidRefresh }
  local raidSrc = at(UI.Text(panel, "note", "From Warcraft Logs of WoW Classic raids (not Forever's own logs): Forever's raids may differ."), 26, -526)
  raidSrc:SetWidth(W_)
  local fight = UI.Slider(panel, "Mana needs to last", 330, 60, 600, 30, S("fightLength"),
    function(v) return v % 60 == 0 and format("%d s (%d min)", v, v / 60) or format("%d s (%.1f min)", v, v / 60) end, Changed)
  fight:SetPoint("TOPLEFT", 26, -556)
  fight.tip = "For healers and casters: how long your mana has to keep you casting, in one fight (a boss fight: about 3 minutes)."
    .. "\n\nOver that time you can spend your mana pool plus what you regain while casting. If your spells would cost more, Equip This! counts them as cast that much less, so Intellect (a bigger pool), Spirit and mana regeneration (mp5) are worth more. Longer fights make regeneration worth more than Intellect."
    .. "\n\nNot used once Equip This! has learned how you fight from your own fights: those already show what your mana let you cast."
  track(fight)

  -- Learning and helping -----------------------------------------------------
  at(UI.Section(panel, "Learning how you fight", W_), 26, -606)
  local learn = track(at(UI.Check(panel, "Learn from my fights (the game's damage meter, after each fight)", E("learn"), W_, Changed), 26, -636))
  learn.tip = "How often you use each ability and spell decides what's worth most to you. Equip This! adds up your damage and healing per spell after each fight and learns from them every few fights. It stays on your computer."
  local share = track(at(UI.Check(panel, "Help improve Equip This!: keep anonymous fight records I can send", E("share"), W_, Changed), 26, -660))
  share.tip = "Off unless you tick it. Each fight is kept as: class, spec, level, fight length, damage and healing per spell, and Equip This!'s own estimate. No name, realm or IDs, and nothing leaves the game on its own: \"Show my records\" gives you the text to paste if you'd like to send it. It helps the classes and specs the author can't test."
  local yEnd = -700
  local recs = at(UI.Button(panel, "Show my records", 150, function() ns.ShowReport() end), 26, yEnd)
  recs.tip = "The records to copy and paste (Ctrl+C)."
  local reset = UI.Button(panel, "Reset build", 110, function() B.ResetBuild(); changed() end)
  reset:SetPoint("LEFT", recs, "RIGHT", 8, 0)
  reset.tip = "Back to Auto: Leveling until the level cap, then Damage (tanks: Tanking)."
  local fb = UI.Button(panel, "Report a bug / suggest", 170, function()
    UI.ShowLink("EquipThisLinkWindow", "Equip This!: bugs and ideas", "https://github.com/califaxop/Equip-This-Upgrade-Advisor/issues/new/choose")
  end)
  fb:SetPoint("LEFT", reset, "RIGHT", 8, 0)
  local hint = at(UI.Text(panel, "note", "Hold Shift on an item for where its numbers come from.  /eqt item <link>: the full working.  /eqn: the engine's diagnostics (/eqn model, /eqn measure)."), 26, yEnd - 30)
  hint:SetWidth(W_)

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
    window = UI.Window("EquipThisOptionsWindow", 742, 790)
    window:SetPoint("CENTER")
    UI.SetHost(window) -- pop-ups (New, Rename, Import, Delete...) sit over this window
    local ok, e = pcall(BuildPanel, window)
    if not ok then window:Hide(); window = nil; ns.Print("settings failed: " .. tostring(e)); return end
    window:SetHeight(window.height or 790)
    window:Hide()
  end
  UI.Restyle()
  window:SetScale(math.max(0.5, math.min(1, (UIParent:GetHeight() - 40) / window:GetHeight())))
  window:SetShown(not window:IsShown())
end
