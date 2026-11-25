-- Bootstrap: the addon's namespace, version, printing, module registry and a safe-call helper.
-- Every other file gets the same namespace table (ns) from the game's addon loader.
local ADDON, ns = ...

ns.name = ADDON
ns.version = "0.4.2"
ns.title = "Equip This! Next"

-- Modules register themselves here so diagnostics can list what loaded.
ns.modules = {}
function ns.Module(name)
  local m = ns.modules[name]
  if not m then
    m = {}
    ns.modules[name] = m
    ns[name] = m
  end
  return m
end

local PREFIX = "|cff33ff99Equip This! Next|r:"
function ns.Print(...) print(PREFIX, ...) end
function ns.Printf(fmt, ...) ns.Print(string.format(fmt, ...)) end

-- Lua errors inside our own code are caught, counted and kept for /eqn status instead of
-- surfacing as game errors. ns.Safe(label, fn, ...) returns ok, results...
ns.errors = { count = 0, recent = {} }
local function pack(...) return { n = select("#", ...), ... } end
function ns.Safe(label, fn, ...)
  local r = pack(pcall(fn, ...))
  if not r[1] then
    local e = ns.errors
    e.count = e.count + 1
    table.insert(e.recent, 1, string.format("%s: %s", tostring(label), tostring(r[2])))
    if #e.recent > 10 then table.remove(e.recent) end
    if ns.db and ns.db.debug then ns.Print("|cffff6060error|r " .. e.recent[1]) end
    return false, r[2]
  end
  return unpack(r, 1, r.n)
end
ns.pack = pack
