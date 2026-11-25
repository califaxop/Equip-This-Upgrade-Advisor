-- Tooltip: the comparison on item tooltips, and the evaluation context shared with /eqn.
-- Uses TooltipDataProcessor.AddTooltipPostCall (Blizzard's tooltip pipeline; used by the released
-- Equip This! on Forever). Nothing is computed in combat; results are cached per item until the
-- character changes.
local _, ns = ...
local TT = ns.Module("Tooltip")
local Cache = ns.Cache

local GOOD, BAD, DIM, NOTE = "|cff40ff40", "|cffff5050", "|cff9d9d9d", "|cffffd200"

function ns.Context()
  if ns.evalContext then return ns.evalContext end
  local p = ns.profile
  if not p then return nil, "not scanned yet" end
  local ctx, why = ns.Evaluator.Context(p, { targetOffset = ns.db and ns.db.targetOffset })
  ns.evalContext = ctx
  return ctx, why
end

function TT.Evaluate(link)
  local cached = Cache.Get("evaluation", link)
  if cached then return cached end
  local ctx, why = ns.Context()
  if not ctx then return { status = "none", why = why } end
  local item = ns.EquipmentScanner.ReadItem(link)
  local res = ns.Evaluator.Compare(ctx, item)
  if res.status ~= "loading" then Cache.Set("evaluation", link, res) end
  return res
end

local function fmt(x)
  if not x then return nil end
  if math.abs(x) < 0.05 then return DIM .. "±0%|r" end
  return (x > 0 and GOOD .. "+" or BAD) .. string.format("%.1f%%", x) .. "|r"
end
TT.Pct = fmt

-- the lines for an item ({ left text } list)
function TT.Lines(res)
  local L = {}
  local head = "|cff33ff99EqT Next:|r "
  if res.status == "loading" then L[1] = head .. DIM .. "loading...|r"; return L end
  if res.status == "later" or res.status == "none" then L[1] = head .. DIM .. tostring(res.why) .. "|r"; return L end
  if res.status == "equipped" then L[1] = head .. DIM .. "equipped|r"; return L end
  local b = res.best
  if not b then L[1] = head .. DIM .. "can't compare yet|r"; return L end
  local parts = {}
  if b.dps then parts[#parts + 1] = "DPS " .. fmt(b.dps) end
  if b.ehp then parts[#parts + 1] = "EHP " .. fmt(b.ehp) end
  if #parts == 0 then parts[1] = DIM .. "no change measured|r" end
  L[1] = head .. table.concat(parts, "  ")
  local where = b.old and not b.old.empty and ("vs " .. (b.old.name or b.slotName)) or ("into the empty " .. b.slotName .. " slot")
  L[2] = DIM .. where .. " · confidence " .. res.confidence .. "|r"
  if res.metric == "ehp" then L[#L + 1] = DIM .. "spell damage / healing: milestone 4|r" end
  return L
end

local function onItem(tooltip)
  if not (ns.db and ns.db.tooltip) or ns.Compat.InCombat() then return end
  local ok, _, link = pcall(tooltip.GetItem, tooltip)
  if not ok or type(link) ~= "string" then return end
  local res = TT.Evaluate(link)
  for _, line in ipairs(TT.Lines(res)) do tooltip:AddLine(line) end
end

ns.Events.On("PLAYER_LOGIN", "tooltip", function()
  local TDP = TooltipDataProcessor
  if TDP and TDP.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    TDP.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tt) ns.Safe("tooltip", onItem, tt) end)
    TT.hooked = true
  end
end)
