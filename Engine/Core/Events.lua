-- (bundled from EquipThisNext: edit it there and run tools/next/bundle.py)
-- Events: one frame, many listeners. Registering an event the client doesn't have is caught and
-- recorded (Events.failed) instead of erroring, so a missing event shows up in /eqn status.
local _, ns = ...; ns = ns.Engine
local Events = ns.Module("Events")

local frame = CreateFrame("Frame")
local listeners = {}   -- event -> { key = fn }
Events.failed = {}     -- event -> error text
Events.seen = {}       -- event -> times fired (diagnostics)

function Events.On(event, key, fn)
  if not listeners[event] then
    local ok, err = pcall(frame.RegisterEvent, frame, event)
    if not ok then
      Events.failed[event] = tostring(err)
      return false
    end
    listeners[event] = {}
  end
  listeners[event][key] = fn
  return true
end

function Events.Off(event, key)
  local l = listeners[event]
  if l then l[key] = nil end
end

frame:SetScript("OnEvent", function(_, event, ...)
  Events.seen[event] = (Events.seen[event] or 0) + 1
  for key, fn in pairs(listeners[event] or {}) do
    ns.Safe(event .. ":" .. key, fn, event, ...)
  end
end)

-- Run fn once, delay seconds after the last call with this key (bursts of events -> one rescan).
local pending = {}
function Events.Debounce(key, delay, fn)
  pending[key] = (pending[key] or 0) + 1
  local mine = pending[key]
  local after = C_Timer and C_Timer.After
  if not after then return ns.Safe(key, fn) end
  after(delay, function()
    if pending[key] == mine then ns.Safe(key, fn) end
  end)
end
