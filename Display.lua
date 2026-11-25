-- Where Equip This! shows up: a line on item tooltips, and a glow on the best quest reward.
local _, ns = ...
local B = ns.Bridge
local D = {}
ns.Display = D

local GREEN, RED, GREY, GOLD = "|cff40ff40", "|cffff5050", "|cff9d9d9d", "|cffffd200"

local ORANGE = "|cffff9933"

-- an item's name in its quality color
local function Named(link)
  local name = type(link) == "string" and link:match("%[(.-)%]")
  if not name then return nil end
  return (link:match("^(|c%x%x%x%x%x%x%x%x)") or "|cffffffff") .. name .. "|r"
end
-- " vs [Item]" (+ the off-hand it'd be paired with; "(bags)" when your best is in your bags)
local function Versus(c)
  local vs = Named(c.vs)
  if not vs then return nil end
  local out = GREY .. "vs|r " .. vs
  if c.inBags then out = out .. " " .. GREY .. "(bags)|r" end
  return out
end

-- what the % is of: "DPS" / "HPS" / "Threat" / "EHP" when your build is all one of them, else nothing (a mix)
function D.Unit()
  local t = B.Mix()
  if t >= 1 then return "EHP" end
  if t <= 0 then return select(2, B.MainMetric()) end
  return ""
end

local function pct(x) return x and format("%s%+.1f%%|r", x >= 0 and GREEN or RED, x) or nil end
-- the separate numbers under the verdict: "DPS +5.1%  EHP -0.3%"
function D.Metrics(c)
  local m, out = c.metrics or {}, {}
  if m.dps and not m.tps then out[#out + 1] = "DPS " .. pct(m.dps) end
  if m.hps then out[#out + 1] = "HPS " .. pct(m.hps) end
  if m.tps then out[#out + 1] = "Threat " .. pct(m.tps) end
  if m.ehp then out[#out + 1] = "EHP " .. pct(m.ehp) end
  return table.concat(out, GREY .. "  ·  |r")
end

local STAT_SHORT = { EFFECTS = "Effects" }
-- the biggest parts of a comparison: "Weapon DPS -8.2%, Strength -1.1%, Stamina +0.2%"
function D.Parts(c, n)
  local list = {}
  for k, v in pairs(c.parts or {}) do
    if math.abs(v) >= 0.05 then list[#list + 1] = { k, v } end
  end
  table.sort(list, function(a, b) return math.abs(a[2]) > math.abs(b[2]) end)
  local out = {}
  for i = 1, math.min(n or 4, #list) do
    local k, v = list[i][1], list[i][2]
    local name = STAT_SHORT[k] or B.StatName(k)
    out[#out + 1] = format("%s %s%+.1f%%|r", name, v > 0 and GREEN or RED, v)
  end
  return out
end

-- "75% damage / 25% survival", "all damage", "all survival": what your build's verdict weighs
function D.BuildMix()
  local t = B.Mix()
  local _, unit = B.MainMetric()
  local word = unit == "HPS" and "healing" or (unit == "Threat" and "threat" or "damage")
  if t <= 0 then return "all " .. word end
  if t >= 1 then return "all survival" end
  return format("%d%% %s / %d%% survival", (1 - t) * 100 + 0.5, word, t * 100 + 0.5)
end

-- The lines for an item, in order (5.0):
--   1. what it's tried with: "paired with [Savage Boar's Guard] (bags)", else "vs [Rage of the Storm]"
--   2. the numbers, apart: "DPS -20.3%  ·  EHP +19.0%"
--   3. the verdict for your build, labelled: "Downgrade -12.4% vs [Rage of the Storm] for your build (75% damage / 25% survival)"
-- An item that can't be compared gets one line ("Equipped", "Can't use it"...). Returns the lines, the comparison.
function D.Lines(link)
  local c = B.Compare(link)
  if not c then return nil end
  local one
  if c.kind == "unusable" then one = GREY .. "Can't use it|r"
  elseif c.kind == "unique" then one = GREY .. "Unique: you already wear one|r"
  elseif c.kind == "equipped" then one = GREY .. "Equipped|r"
  elseif c.kind == "twohand" then one = GREY .. "Off-hand: you use a two-hander (no one-hander in your bags to pair it with)|r"
  elseif c.kind == "armortype" then one = GREY .. "Not " .. c.best .. " (your setting)|r" end
  if one then return { GOLD .. "Equip This!:|r " .. one }, c end
  local vs = Named(c.vs)
  local hand = c.hand == "oh" and (" " .. GREY .. "(off-hand)|r") or ""
  local L = {}
  local partner = Named(c.partner)
  if partner then
    L[1] = GOLD .. "Equip This!:|r " .. GREY .. "paired with|r " .. partner .. " " .. GREY .. "(bags)|r"
  elseif c.kind == "new" then
    L[1] = GOLD .. "Equip This!:|r " .. GREY .. "into your empty slot|r" .. hand
  else
    L[1] = GOLD .. "Equip This!:|r " .. GREY .. "vs|r " .. (vs or "?") .. hand
  end
  local m = D.Metrics(c)
  if m ~= "" then L[#L + 1] = m .. (c.confidence == "low" and (GREY .. "  ·  " .. ORANGE .. "rough|r") or "") end
  local col = (c.kind == "upgrade" or c.kind == "new") and GREEN or (c.kind == "downgrade" and RED or GREY)
  local word = (c.kind == "upgrade" or c.kind == "new") and "Upgrade" or (c.kind == "downgrade" and "Downgrade" or "About the same")
  local verdict = col .. word .. (c.kind ~= "same" and format(" %+.1f%%", c.pct or 0) or "") .. "|r"
  if partner and vs then verdict = verdict .. " " .. GREY .. "vs|r " .. vs end
  L[#L + 1] = verdict .. " " .. GREY .. "for your build (" .. D.BuildMix() .. ")|r"
  if c.enchant then L[#L + 1] = GREY .. "with your " .. c.enchant .. " on it|r" end
  return L, c
end

-- (one line, for other places: the verdict with its %)
function D.Verdict(link)
  local L = D.Lines(link)
  return L and L[#L] or nil
end

---------------------------------------------------------------------------
-- Item tooltips
---------------------------------------------------------------------------
local function OnItemTooltip(tip, data)
  if not (ns.db and ns.db.tooltip) then return end
  local link
  if tip.GetItem then
    local ok, _, l = pcall(tip.GetItem, tip)
    if ok and type(l) == "string" then link = l end
  end
  -- comparison tooltips may not answer GetItem: use what the tooltip was built from
  if not link and type(data) == "table" then
    if type(data.hyperlink) == "string" then link = data.hyperlink
    elseif data.guid and C_Item and C_Item.GetItemLinkByGUID then
      local ok, l = pcall(C_Item.GetItemLinkByGUID, data.guid)
      if ok and type(l) == "string" then link = l end
    end
  end
  if not link then return end
  local L, c = D.Lines(link)
  if L then
    -- each line wraps at the tooltip's own width (it never makes the tooltip wider)
    for _, l in ipairs(L) do tip:AddLine(l, 1, 1, 1, true) end
    if c and c.metrics then
      if c.pvp then
        local pv = {}
        if c.pvp.burst then pv[#pv + 1] = "burst " .. pct(c.pvp.burst) end
        if c.pvp.sustained then pv[#pv + 1] = "sustained " .. pct(c.pvp.sustained) end
        if c.pvp.ehp then pv[#pv + 1] = "survival " .. pct(c.pvp.ehp) end
        if #pv > 0 then tip:AddLine(GREY .. "PvP:|r " .. table.concat(pv, "  "), 1, 1, 1, true) end
      end
      -- the engine's notes (the pairing is the first line already)
      local shown = 0
      for _, n in ipairs(c.notes or {}) do
        if shown < 3 and not n:find("from your bags") then shown = shown + 1; tip:AddLine(GREY .. n .. "|r", 1, 1, 1, true) end
      end
    end
    -- holding Shift: where it comes from, effects it couldn't count, how sure it is
    if IsShiftKeyDown and IsShiftKeyDown() and c and c.metrics then
      local parts = D.Parts(c, 5)
      if #parts > 0 then tip:AddLine(GREY .. "From:|r " .. table.concat(parts, ", "), 1, 1, 1, true) end
      if c.unread then tip:AddLine(ORANGE .. "Not counted: " .. c.unread .. "|r", 1, 1, 1, true) end
      if c.confidence then
        tip:AddLine(GREY .. "Confidence " .. c.confidence .. ((c.reasons and #c.reasons > 0) and (": " .. table.concat(c.reasons, "; ")) or "") .. "|r", 1, 1, 1, true)
      end
      tip:AddLine(GREY .. "For " .. B.ScoringLabel() .. "|r", 1, 1, 1, true)
    end
    tip:Show()
  end
end

function D.HookTooltips()
  if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tip, data)
      if tip == GameTooltip or tip == ItemRefTooltip or (tip.GetName and (tip:GetName() or ""):find("ShoppingTooltip")) then
        OnItemTooltip(tip, data)
      end
    end)
  elseif GameTooltip and GameTooltip.HookScript then
    pcall(GameTooltip.HookScript, GameTooltip, "OnTooltipSetItem", OnItemTooltip)
    if ItemRefTooltip then pcall(ItemRefTooltip.HookScript, ItemRefTooltip, "OnTooltipSetItem", OnItemTooltip) end
  end
end

---------------------------------------------------------------------------
-- Quest rewards: the best upgrade among the choices glows; with no upgrade, the one that sells
-- for most gets a coin
---------------------------------------------------------------------------
local marks = {}

local function Mark(button, kind, text)
  local m = marks[button]
  if not m then
    m = CreateFrame("Frame", nil, button)
    m:SetAllPoints(button.Icon or button.icon or button)
    m:SetFrameLevel(button:GetFrameLevel() + 5)
    m.glow = m:CreateTexture(nil, "OVERLAY")
    m.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    m.glow:SetBlendMode("ADD")
    m.glow:SetPoint("CENTER")
    m.label = m:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    m.label:SetPoint("TOPLEFT", m, "TOPRIGHT", 4, 2)
    m.coin = m:CreateTexture(nil, "OVERLAY")
    m.coin:SetTexture("Interface\\MoneyFrame\\UI-GoldIcon")
    m.coin:SetSize(14, 14)
    m.coin:SetPoint("TOPLEFT", -4, 4)
    m.pulse = m:CreateAnimationGroup()
    m.pulse:SetLooping("BOUNCE")
    local a = m.pulse:CreateAnimation("Alpha")
    a:SetFromAlpha(1); a:SetToAlpha(0.35); a:SetDuration(0.7)
    marks[button] = m
  end
  local w = (button.Icon or button.icon or button):GetWidth() or 36
  m.glow:SetSize(w * 1.9, w * 1.9)
  if kind == "best" then
    m.glow:SetVertexColor(0.3, 1, 0.3); m.glow:Show(); m.coin:Hide(); m.pulse:Play()
  else
    m.glow:Hide(); m.coin:Show(); m.pulse:Stop()
  end
  m.label:SetText(text or "")
  m:Show()
end

local function ClearMarks() for _, m in pairs(marks) do m:Hide(); m.pulse:Stop() end end

-- the reward buttons for the choices, by choice index
local function ChoiceButtons()
  local out = {}
  local frame = QuestInfoRewardsFrame or QuestInfoFrame and QuestInfoFrame.rewardsFrame
  if not frame then return out end
  local list = frame.RewardButtons
  if type(list) ~= "table" then
    list = {}
    for i = 1, 10 do
      local b = _G["QuestInfoRewardsFrameQuestInfoItem" .. i] or _G["QuestInfoItem" .. i]
      if b then list[#list + 1] = b end
    end
  end
  for _, b in ipairs(list) do
    if b:IsShown() and b.type == "choice" and b.GetID then out[b:GetID()] = b end
  end
  return out
end

local pendingLoad = false
function D.MarkRewards()
  ClearMarks()
  if not (ns.db and ns.db.rewards) then return end
  local n = GetNumQuestChoices and GetNumQuestChoices() or 0
  if n < 2 then return end -- one reward (or none): nothing to choose
  local best, bestDelta, rich, richSell, missing = nil, 0, nil, 0, false
  for i = 1, n do
    local link = GetQuestItemLink and GetQuestItemLink("choice", i)
    local c = link and B.Compare(link)
    local f = link and B.Facts(link)
    if link and not f then missing = true end
    if c and (c.kind == "upgrade" or c.kind == "new") and (c.pct or 0) > bestDelta then best, bestDelta = i, c.pct end
    if f and f.sell > richSell then rich, richSell = i, f.sell end
  end
  if missing and not pendingLoad then -- item data still loading: try again in a moment
    pendingLoad = true
    C_Timer.After(0.5, function() pendingLoad = false; D.MarkRewards() end)
  end
  local buttons = ChoiceButtons()
  if best and buttons[best] then
    Mark(buttons[best], "best", "|cff40ff40Best for " .. B.ScoringLabel() .. "|r")
  elseif rich and ns.db.sellFallback and buttons[rich] then
    Mark(buttons[rich], "sell", "|cffffd200Sells for most|r")
  end
end

function D.HookRewards()
  if hooksecurefunc and QuestInfo_Display then
    hooksecurefunc("QuestInfo_Display", function() C_Timer.After(0, D.MarkRewards) end)
  end
  local ev = CreateFrame("Frame")
  for _, e in ipairs({ "QUEST_COMPLETE", "QUEST_DETAIL", "QUEST_FINISHED" }) do pcall(ev.RegisterEvent, ev, e) end
  ev:SetScript("OnEvent", function(_, e)
    if e == "QUEST_FINISHED" then ClearMarks() else C_Timer.After(0.1, D.MarkRewards) end
  end)
end
