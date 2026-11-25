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
  local ctx, why = ns.Evaluator.Context(p, { targetOffset = ns.db and ns.db.targetOffset, confirmed = ns.db and ns.db.confirmed,
    rotation = ns.db and ns.db.rotation, lastMeasurement = ns.db and ns.db.measurements and ns.db.measurements[1] })
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
  if res.status == "none" or res.status == "cantuse" or res.status == "unknown" then L[1] = head .. DIM .. tostring(res.why) .. "|r"; return L end
  if res.status == "equipped" then L[1] = head .. DIM .. "equipped|r"; return L end
  if res.status == "unique" then L[1] = head .. DIM .. "unique: you already wear one|r"; return L end
  local b = res.best
  if not b then L[1] = head .. DIM .. "can't compare yet|r"; return L end
  local parts = {}
  if b.dps then parts[#parts + 1] = "DPS " .. fmt(b.dps) end
  if b.hps then parts[#parts + 1] = "HPS " .. fmt(b.hps) end
  if b.ehp then parts[#parts + 1] = "EHP " .. fmt(b.ehp) end
  if #parts == 0 then parts[1] = DIM .. "no change measured|r" end
  L[1] = head .. table.concat(parts, "  ")
  local names = {}
  for _, it in ipairs(b.removed or {}) do names[#names + 1] = it.name or "?" end
  local where = #names > 0 and ("vs " .. table.concat(names, " + ")) or ("into the empty " .. tostring(b.slotName) .. " slot")
  L[2] = DIM .. where .. " · confidence " .. res.confidence .. "|r"
  for _, n in ipairs(b.notes or {}) do L[#L + 1] = DIM .. n .. "|r" end
  for _, n in ipairs(res.notes or {}) do L[#L + 1] = NOTE .. n .. "|r" end
  if b.carry and #b.carry > 0 then L[#L + 1] = DIM .. "with your enchant on it (" .. table.concat(b.carry, "; ") .. ")|r" end
  for _, t in ipairs(b.setGained or {}) do L[#L + 1] = GOOD .. "set bonus gained: " .. t .. "|r" end
  for _, t in ipairs(b.setLost or {}) do L[#L + 1] = BAD .. "set bonus lost: " .. t .. "|r" end

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
