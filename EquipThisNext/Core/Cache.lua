-- Cache: separate stores per kind of data (item, character, talents, profile, evaluation), each
-- emptied by the events that can change it. A stored value can carry a fingerprint: Get with a
-- fingerprint returns it only if they still match (e.g. a profile built for the same gear+talents).
-- Pure Lua: no game API, so it's tested outside the game.
local _, ns = ...
local Cache = ns.Module("Cache")

Cache.KINDS = { "item", "character", "talents", "profile", "evaluation" }
local stores = {}
Cache.generation = {}   -- kind -> how many times it was emptied
Cache.hits, Cache.misses = {}, {}

for _, k in ipairs(Cache.KINDS) do stores[k] = {}; Cache.generation[k] = 0; Cache.hits[k] = 0; Cache.misses[k] = 0 end

function Cache.Get(kind, key, fingerprint)
  local s = stores[kind]
  local e = s and s[key]
  if e and (fingerprint == nil or e.fp == fingerprint) then
    Cache.hits[kind] = Cache.hits[kind] + 1
    return e.value
  end
  Cache.misses[kind] = (Cache.misses[kind] or 0) + 1
  return nil
end

function Cache.Set(kind, key, value, fingerprint)
  if not stores[kind] then stores[kind] = {}; Cache.generation[kind] = 0; Cache.hits[kind] = 0; Cache.misses[kind] = 0 end
  stores[kind][key] = { value = value, fp = fingerprint }
  return value
end

function Cache.Invalidate(kind, key)
  if not stores[kind] then return end
  if key ~= nil then stores[kind][key] = nil; return end
  stores[kind] = {}
  Cache.generation[kind] = (Cache.generation[kind] or 0) + 1
end

function Cache.Count(kind)
  local n = 0
  for _ in pairs(stores[kind] or {}) do n = n + 1 end
  return n
end

-- A deterministic text fingerprint of a plain Lua value (sorted keys; tables nested).
local function fp(v, out)
  local t = type(v)
  if t == "table" then
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b)
      local ta, tb = type(a), type(b)
      if ta ~= tb then return ta < tb end
      return a < b
    end)
    out[#out + 1] = "{"
    for _, k in ipairs(keys) do
      out[#out + 1] = tostring(k) .. "="
      fp(v[k], out)
      out[#out + 1] = ";"
    end
    out[#out + 1] = "}"
  elseif t == "number" then
    out[#out + 1] = "n" .. string.format("%.6g", v)
  elseif t == "string" then
    out[#out + 1] = "s" .. string.format("%q", v)
  else
    out[#out + 1] = t:sub(1, 1) .. tostring(v)
  end
end
function Cache.Fingerprint(v)
  local out = {}
  fp(v, out)
  return table.concat(out)
end
