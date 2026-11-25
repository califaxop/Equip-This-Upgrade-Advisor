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

-- Short: "Downgrade -11.3% DPS vs [Rage of the Storm]" (paired with an off-hand, against your two-hander)
function D.Verdict(link)
  local c = B.Compare(link)
  if not c then return nil end
  if c.kind == "unusable" then return GREY .. "Can't use it|r" end
  if c.kind == "unique" then return GREY .. "Unique: you already wear one|r" end
  if c.kind == "equipped" then
    local what = c.equipLoc == "INVTYPE_TRINKET" and "trinket" or "ring"
    if c.pair == "weaker" then return GREY .. "Equipped|r " .. ORANGE .. "- your weaker " .. what .. " (replaced first)|r" end
    if c.pair == "stronger" then return GREY .. "Equipped - your stronger " .. what .. "|r" end
    if c.pair == "equal" then return GREY .. "Equipped - your " .. what .. "s are equal|r" end
    return GREY .. "Equipped|r"
  end
  if c.kind == "twohand" then return GREY .. "Off-hand: you use a two-hander (no one-hander in your bags to pair it with)|r" end
  if c.kind == "armortype" then return GREY .. "Not " .. c.best .. " (your setting)|r" end
  local u = D.Unit()
  local unit = (u ~= "") and (" " .. u) or ""
  local tail = c.enchant and (" " .. GREY .. "(with your " .. c.enchant .. " on it)|r") or ""
  if c.kind == "new" then return format("%sUpgrade %+.1f%%%s|r %s(empty slot)|r%s", GREEN, c.pct or 0, unit, GREY, tail) end
  if c.kind == "same" then return GREY .. "About the same|r" .. tail, Versus(c) end
  local col = c.kind == "upgrade" and GREEN or RED
  local word = c.kind == "upgrade" and "Upgrade" or "Downgrade"
  local lead = ""
  local partner = Named(c.partner)
  if partner then lead = GREY .. "paired with|r " .. partner .. " " .. GREY .. "-|r " end
  if c.hand == "oh" then tail = " " .. GREY .. "(off-hand)|r" .. tail end
  return format("%s%s%s %+.1f%%%s|r%s", lead, col, word, c.pct, unit, tail), Versus(c)
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
  local v, vs = D.Verdict(link)
  if v then
    -- one line, wrapped at the tooltip's own width (it never makes the tooltip wider)
    tip:AddLine(GOLD .. "Equip This!:|r " .. v .. (vs and (" " .. vs) or ""), 1, 1, 1, true)
    local c = B.Compare(link)
    if c and c.metrics then
      local m = D.Metrics(c)
      if m ~= "" then tip:AddLine(m .. (c.confidence == "low" and (GREY .. "  ·  " .. ORANGE .. "rough|r") or ""), 1, 1, 1, true) end
      if c.pvp then
        local pv = {}
        if c.pvp.burst then pv[#pv + 1] = "burst " .. pct(c.pvp.burst) end
        if c.pvp.sustained then pv[#pv + 1] = "sustained " .. pct(c.pvp.sustained) end
        if c.pvp.ehp then pv[#pv + 1] = "survival " .. pct(c.pvp.ehp) end
        if #pv > 0 then tip:AddLine(GREY .. "PvP:|r " .. table.concat(pv, "  "), 1, 1, 1, true) end
      end
      for i, n in ipairs(c.notes or {}) do
        if i > 3 then break end
        tip:AddLine(GREY .. n .. "|r", 1, 1, 1, true)
      end
    end
    -- holding Shift: where it comes from, effects it couldn't count, how sure it is
    if IsShiftKeyDown and IsShiftKeyDown() and c then
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
