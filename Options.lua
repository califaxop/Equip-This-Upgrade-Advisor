-- Settings window (/eqt), in the game's own Settings design (Settings.lua).
local _, ns = ...
local UI = ns.UI
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
    w = UI.Popup("EquipThisExportWindow", 640, 400, "Submit Your Fight Logs")
    exportWin = w
    w.url = UI.Edit(w, 580, { function() return SUBMIT_URL end, function() end })
    w.url:SetPoint("TOP", 0, -44)
    w.url:HookScript("OnTextChanged", function(self, user) if user and self:GetText() ~= SUBMIT_URL then self:SetText(SUBMIT_URL); self:HighlightText() end end)
    w.url:HookScript("OnEditFocusGained", function(self) self:HighlightText() end)
    local note = UI.Font(w, "GameFontHighlightSmall", "Copy the line below and paste it into the form at the link above (needs a GitHub account), or into a comment on Equip This!'s CurseForge page. "
      .. "It holds this session's fights (unsent ones are cleared when you log in again), so please send it before you log out. It helps the classes and specs the author can't play.")
    note:SetPoint("TOP", 0, -74); note:SetWidth(580); note:SetJustifyH("CENTER")
    w.line = UI.Edit(w, 580, { function() return w.text or "" end, function() end })
    w.line:SetPoint("TOP", 0, -134)
    w.line:HookScript("OnTextChanged", function(self, user) if user and self:GetText() ~= w.text then self:SetText(w.text or ""); self:HighlightText() end end)
    w.line:HookScript("OnEditFocusGained", function(self) self:HighlightText() end)
    UI.Divider(w, -162, 30, 30)
    -- what's in it (counters), two columns
    w.stats = {}
    local ICONS = { "Interface\\Icons\\Ability_DualWield", "Interface\\Icons\\INV_Misc_PocketWatch_01", "Interface\\Icons\\INV_Misc_Book_09",
      "Interface\\Icons\\Spell_Nature_LightningShield", "Interface\\Icons\\INV_Misc_Note_01", "Interface\\Icons\\Achievement_Level_10" }
    for i = 1, 6 do
      local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
      local icon = w:CreateTexture(nil, "ARTWORK")
      icon:SetTexture(ICONS[i]); icon:SetSize(18, 18)
      icon:SetPoint("TOPLEFT", 40 + col * 300, -176 - row * 26)
      local t = UI.Font(w, "GameFontNormal")
      t:SetPoint("LEFT", icon, "RIGHT", 8, 0)
      w.stats[i] = t
    end
    local inc = UI.Font(w, "GameFontHighlightSmall", INCLUDED)
    inc:SetPoint("TOP", 0, -262); inc:SetWidth(580); inc:SetJustifyH("CENTER")
    local inside = UI.Button(w, "What's inside", 130, function()
      local text = FR.ReportText()
      -- (in the export window's place; closing it brings the export window back)
      w:Hide()
      UI.ShowText("EquipThisInsideWindow", "What's inside, fight by fight", INCLUDED, text, function() ns.ShowReport() end)
    end)
    inside:SetPoint("BOTTOMLEFT", 18, 16)
    inside.tip = "The same records, one fight a line, in plain words."
    w.done = UI.Button(w, "I reported this", 150, function()
      local n = FR.MarkReported()
      ns.Print(format("thank you! %d fight record(s) marked as sent; the next export holds only new ones.", n))
      ns.ShowReport()
    end)
    w.done:SetPoint("BOTTOM", 60, 16)
    w.done.tip = "Once you've sent it: the next export holds only fights recorded after now."
    local close = UI.Button(w, CLOSE or "Close", 110, function() w:Hide() end)
    close:SetPoint("BOTTOMRIGHT", -16, 16)
  end
  local line, n = FR.ExportString()
  local sum = FR.Summary()
  local share = ns.Engine.db and ns.Engine.db.share
  w.text = n > 0 and line or (share and "(no fights recorded since your last export: play a few and come back)"
    or "(nothing recorded: tick \"Help improve Equip This!\" in /eqt to start)")
  w.url:SetText(SUBMIT_URL)   -- (set on every open: the box only fills itself when it loses focus)
  w.url:SetCursorPosition(0)
  w.line:SetText(w.text)
  local G = "|cffffffff"
  local specs = #sum.specs > 0 and (sum.specs[1] .. (#sum.specs > 1 and format(" +%d more", #sum.specs - 1) or "")) or "-"
  w.stats[1]:SetText("Fights recorded: " .. G .. sum.fights .. "|r")
  w.stats[2]:SetText("Time in combat: " .. G .. hms(sum.seconds) .. "|r")
  w.stats[3]:SetText("Spells tracked: " .. G .. sum.spells .. "|r")
  w.stats[4]:SetText("Specs: " .. G .. specs .. "|r")
  w.stats[5]:SetText("Sent before: " .. G .. sum.sentBefore .. " fights|r")
  w.stats[6]:SetText("Levels: " .. G .. (sum.levels and (sum.levels[1] == sum.levels[2] and sum.levels[1] or (sum.levels[1] .. "-" .. sum.levels[2])) or "-") .. "|r")
  w.done:SetEnabled(n > 0)
  w:Place(); w:Show()
  w.line:SetFocus(); w.line:HighlightText()
end

-- the reminder in chat (twice a week at most: after Wednesday's maintenance and on Sunday, with 25+ new records; the engine decides when)
function ns.RemindToShare(n)
  ns.Print(format("You have %d new fight logs to submit (optional). They're kept for this session only (cleared when you log in again), so please submit them before you log out. "
    .. "|cff40ff40|Haddon:EquipThis:records|h[Click here to submit them]|h|r", n))
end

local B -- (ns.Bridge)
local function Now() return "Comparing gear for: " .. B.ScoringLabel() end

local function PageSpec(_, R)
  R:Section("Your spec")
  local opts = { { "auto", "Auto: from my talents" } }
  for _, t in ipairs(B.TREES[ns.Class()] or {}) do opts[#opts + 1] = { t, t } end
  local now
  R:Selector("Spec", 300, opts, S("spec"), function() Changed(); R.Refresh() end, "Auto uses the talent tree you've put the most points in.")
  now = R:Note("")
  R:Track({ Refresh = function() now:SetText(Now()) end })
end

local function PageShow(_, R)
  R:Section("On tooltips")
  R:Check("Upgrade or downgrade", S("tooltip"), Changed, "On item tooltips.")
  R:Check("PvP numbers too", S("pvp"), Changed, "Burst, sustained damage and survival against a player of your level armored like you: no glancing blows, half the damage you take is magic. Separate from the PvE numbers.")
  R:Check("Only my best armor type", S("bestArmorOnly"), Changed, "From level 40, only mail (shamans and hunters) or plate (warriors and paladins) can be an upgrade. Off by default: Forever has no armor specialization, so a lighter piece with better stats really is better.")
  R:Section("Quest rewards")
  R:Check("Glow the best quest reward", S("rewards"), Changed)
  R:Check("No upgrade: mark the best to sell", S("sellFallback"), Changed, "No upgrade among the rewards: mark the one that sells for most.", true)
end

local function PageBuild(_, R)
  local function changed() Changed(); R.Refresh() end
  R:Section("Your build")
  R:Note("Each item is worked out on your own character: your stats, talents, abilities, weapon imbue and procs, and how you really fight. Damage (or healing, or threat for tanks) and survivability are shown apart; the slider says how they weigh in the Upgrade / Downgrade verdict.")
  local buildOpts, buildTip = {}, {}
  for _, b in ipairs(B.BUILDS) do
    buildOpts[#buildOpts + 1] = { b[1], B.BuildName(b[1]) }
    buildTip[#buildTip + 1] = B.BuildName(b[1]) .. ": " .. b[5]
  end
  R:Selector("Build", 260, buildOpts,
    { function() local c = ns.db.builds and ns.db.builds[B.SpecKey()]; return c and c.build or "auto" end, function(v) B.SetBuild(v) end }, changed,
    table.concat(buildTip, "\n") .. "\nMoving the slider below makes it your own mix.")
  local function main() local _, u = B.MainMetric(); return u == "HPS" and "healing" or (u == "Threat" and "threat" or "damage") end
  local _, mixRow = R:Slider("Weighing", 0, 1, 0.05, { function() return B.Mix() end, function(v) B.SetMix(v) end },
    function(t) return format("%d%% %s, %d%% survivability", (1 - t) * 100 + 0.5, main(), t * 100 + 0.5) end, changed,
    "Left: more damage (healing, threat); right: more survivability.", nil, 180)
  R:Track({ Refresh = function() mixRow.label:SetText("Weighing " .. main()) end })
  local tank = R:Check("I tank", { function() return B.IsTank() end, function(v) B.SetTank(v) end }, changed,
    "Score threat and survivability as a tank: threat (your damage times your stance, form or aura's threat, from Forever's own data) takes damage's place, and survivability counts as a tank's. Protection always tanks; a Defensive Stance, Bear Form or Righteous Fury does too.")
  local tr = tank.Refresh
  tank.Refresh = function() tr(); tank.SetActive(not B.IsTankSpec()) end
  local raidOpts = {}
  for _, k in ipairs(B.RAID_ORDER) do raidOpts[#raidOpts + 1] = { k, B.RAIDS[k].name } end
  local raid, raidRow = R:Selector("Raid at 60", 260, raidOpts, { function() return B.Raid() end, function(v) B.SetRaid(v) end }, changed,
    "At the level cap, survivability counts how much of what hits you in the raid you're gearing for is magic. Measured on Warcraft Logs from WoW Classic (Era) raids, not Forever's own: Forever's versions of these raids may hit differently. Kept per character. While leveling, a fifth (assumed).")
  local raidNote = UI.Note(raidRow, "")
  raidNote:SetPoint("LEFT", raid, "RIGHT", 10, 0)
  R:Track({ Refresh = function()
    local r = B.RAIDS[B.Raid()]
    raidNote:SetText(format("%d%% of what hits %s is magic", (B.IsTank() and r.tank or r.other) * 100 + 0.5, B.IsTank() and "a tank" or "you"))
  end })
  R:Slider("Mana needs to last", 60, 600, 30, S("fightLength"),
    function(v) return v % 60 == 0 and format("%d s (%d min)", v, v / 60) or format("%d s (%.1f min)", v, v / 60) end, Changed,
    "For healers and casters: how long your mana has to keep you casting, in one fight (a boss fight: about 3 minutes).\n\nOver that time you can spend your mana pool plus what you regain while casting. If your spells would cost more, Equip This! counts them as cast that much less, so Intellect (a bigger pool), Spirit and mana regeneration (mp5) are worth more. Longer fights make regeneration worth more than Intellect.\n\nNot used once Equip This! has learned how you fight from your own fights: those already show what your mana let you cast.")
  R:Button("Start again", "Reset build", 110, function() B.ResetBuild(); changed() end,
    "Back to Auto: Leveling until the level cap, then Damage (tanks: Tanking).")
end

local function PageFights(_, R)
  R:Section("Learning how you fight")
  R:Check("Learn from my fights", E("learn"), Changed, "From the game's damage meter, after each fight: how often you use each ability and spell decides what's worth most to you. Equip This! adds up your damage and healing per spell after each fight and learns from them every few fights. It stays on your computer.")
  R:Section("Helping improve Equip This!")
  R:Check("Keep anonymous fight logs", E("share"), Changed, "Off unless you tick it. Each fight is kept as: class, spec, level, fight length, damage and healing per spell, and Equip This!'s own estimate. No name, realm or IDs, and nothing leaves the game on its own: \"Submit\" gives you the form's link and the text to paste into it. It helps the classes and specs the author can't test.")
  R:Button("Submit fight logs", "Submit", 96, function() ns.ShowReport() end,
    "Send your fight logs to help improve Equip This! for your class and spec: opens the form's link and your logs, ready to copy and paste (Ctrl+C).")
end

local function PageStatus(_, R)
  R:Section("Now")
  local now = R:Note("")
  R:Track({ Refresh = function() now:SetText(Now()) end })
  R:Section("Commands")
  R:Note("Hold Shift on an item for where its numbers come from.  /eqt item <link>: the full working.  /eqn: the engine's diagnostics (/eqn model, /eqn measure).  /eqt bug: the bug report.")
end

local function BuildWindow()
  B = ns.Bridge
  window = UI.Settings({ name = "EquipThisOptionsWindow", title = "Equip This!", logo = "Interface\\AddOns\\EquipThis\\media\\Logo",
    tagline = "Which gear is better for you.", bug = function() ns.ShowBugReport() end,
    pages = {
      { "Spec", "The talent tree gear is compared for.", PageSpec },
      { "Show", "Upgrades on tooltips, PvP numbers, and quest rewards.", PageShow },
      { "Your Build", "How damage and survivability weigh, tanking, your raid, and mana.", PageBuild },
      { "Fight Logs", "Learning from your fights, and sending them to help improve Equip This!.", PageFights },
      { "Status", "What gear is compared for, and the commands.", PageStatus },
    },
    categories = { { "Equip This!", { 1, 2, 3, 4 } }, { "Help", { 5 } } } })
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

-- Report a bug (the title bar's button, /eqt bug): the line to paste and its counters. (/eqt report is
-- the fight records above.)
local function yes(v) return v and "yes" or "no" end
local function BugReport()
  local Br, En, db = ns.Bridge, ns.Engine, ns.db
  local _, class = UnitClass("player")
  local build, auto = Br.Build()
  local L = { format("Equip This! %s; %s %d; scoring for %s (%s%s, %d%% survival)", tostring(AddonVersion() or "?"), tostring(class), UnitLevel("player"),
    tostring(Br.Tree() or "?"), Br.BuildName(build), auto and ", auto" or "", Br.Mix() * 100 + 0.5) }
  L[#L + 1] = format("settings: spec %s, tooltip %s, rewards %s, sell fallback %s, best armor only %s, PvP %s, fight %ds, learn %s, share %s",
    tostring(db.spec), yes(db.tooltip), yes(db.rewards), yes(db.sellFallback), yes(db.bestArmorOnly), yes(db.pvp), db.fightLength or 0,
    yes(En.db and En.db.learn), yes(En.db and En.db.share))
  L[#L + 1] = format("FlareUI: %s; EllesmereUI: %s", yes(type(FlareUI) == "table"), yes(type(EllesmereUI) == "table"))
  local Diag = En.Diagnostics
  for _, l in ipairs(Diag and Diag.StatusLines and Diag.StatusLines() or { "engine diagnostics not loaded" }) do L[#L + 1] = l end
  local errs = En.errors and En.errors.count or 0
  local sum = En.FightRecorder and En.FightRecorder.Summary()
  return table.concat(L, " // "), {
    { "Interface\\Icons\\INV_Sword_04", "Scoring for", Br.ScoringLabel() },
    { "Interface\\Icons\\INV_Misc_Note_01", "Errors caught", errs },
    { "Interface\\Icons\\INV_Misc_Book_09", "Learning from fights", yes(En.db and En.db.learn) },
    { "Interface\\Icons\\Ability_DualWield", "Fight logs to submit", sum and sum.fights or 0 },
  }
end
local BUG = { name = "EquipThisBugWindow", title = "Equip This! Bugs & Feedback",
  repo = "https://github.com/califaxop/Equip-This-Upgrade-Advisor/issues/new",
  included = "Included: Equip This!'s version, the game client, your class, level and spec, its settings and what its engine saw (scans, hidden stats, errors caught). Never: your name, realm, guild or other players.",
  build = BugReport }
function ns.ShowBugReport(kind)
  BUG.version = AddonVersion()
  return UI.ShowBugReport(BUG, kind)
end

function ns.OpenOptions()
  if not window then
    local ok, e = pcall(BuildWindow)
    if not ok then if window then window:Hide() end; window = nil; ns.Print("settings failed: " .. tostring(e)); return end
  end
  UI.ToggleWindow(window)
  return window
end
