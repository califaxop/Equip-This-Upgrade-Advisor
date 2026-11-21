-- Where Equip This! shows up: a line on item tooltips, and a glow on the best quest reward.
local _, ns = ...
local S = ns.Score
local D = {}
ns.Display = D

local GREEN, RED, GREY, GOLD = "|cff40ff40", "|cffff5050", "|cff9d9d9d", "|cffffd200"

-- "Upgrade +12% (Elemental)" etc., or nil
function D.Verdict(link)
  local key = ns.SpecKey()
  local c = S.Compare(link, ns.Weights(key))
  if not c then return nil end
  local spec = ns.SpecName(key)
  if c.kind == "unusable" then return GREY .. "Can't use it|r" end
  if c.kind == "equipped" then return GREY .. "Equipped|r" end
  if c.kind == "twohand" then return GREY .. "Off-hand: you use a two-hander|r" end
  if c.kind == "new" then return GREEN .. "Upgrade (empty slot)|r " .. GREY .. "(" .. spec .. ")|r" end
  if c.kind == "same" then return GREY .. "About the same|r " .. GREY .. "(" .. spec .. ")|r" end
  local col = c.kind == "upgrade" and GREEN or RED
  local word = c.kind == "upgrade" and "Upgrade" or "Downgrade"
  return format("%s%s %+d%%|r %s(%s)|r", col, word, math.floor(c.pct + (c.pct > 0 and 0.5 or -0.5)), GREY, spec)
end

---------------------------------------------------------------------------
-- Item tooltips
---------------------------------------------------------------------------
local function OnItemTooltip(tip)
  if not (ns.db and ns.db.tooltip) or not tip.GetItem then return end
  local ok, _, link = pcall(tip.GetItem, tip)
  if not (ok and type(link) == "string") then return end
  local v = D.Verdict(link)
  if v then
    tip:AddLine(GOLD .. "Equip This!:|r " .. v)
    tip:Show()
  end
end

function D.HookTooltips()
  if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tip)
      if tip == GameTooltip or tip == ItemRefTooltip or (tip.GetName and (tip:GetName() or ""):find("ShoppingTooltip")) then
        OnItemTooltip(tip)
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
  local weights = ns.Weights()
  local best, bestDelta, rich, richSell, missing = nil, 0, nil, 0, false
  for i = 1, n do
    local link = GetQuestItemLink and GetQuestItemLink("choice", i)
    local c = link and S.Compare(link, weights)
    local f = link and S.Facts(link)
    if link and not f then missing = true end
    if c and (c.kind == "upgrade" or c.kind == "new") and (c.delta or 0) > bestDelta then best, bestDelta = i, c.delta end
    if f and f.sell > richSell then rich, richSell = i, f.sell end
  end
  if missing and not pendingLoad then -- item data still loading: try again in a moment
    pendingLoad = true
    C_Timer.After(0.5, function() pendingLoad = false; D.MarkRewards() end)
  end
  local buttons = ChoiceButtons()
  if best and buttons[best] then
    Mark(buttons[best], "best", "|cff40ff40Best for " .. ns.SpecName(ns.SpecKey()) .. "|r")
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
