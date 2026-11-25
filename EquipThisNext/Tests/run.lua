-- Offline test runner (Lua 5.1, outside the game):  cd EquipThisNext && lua Tests/run.lua
-- Loads the mock API, then every addon file in the .toc's order (exactly as the game does: each
-- file gets the addon name and the shared namespace), then the test files. Exit code 1 on failure.
ROOT = ROOT or "./"
local ADDON = "EquipThisNext"

local function readLines(path)
  local f = assert(io.open(path, "r"))
  local lines = {}
  for l in f:lines() do lines[#lines + 1] = l end
  f:close()
  return lines
end

function LoadAddon()
  local ns = {}
  for _, line in ipairs(readLines(ROOT .. ADDON .. ".toc")) do
    line = line:gsub("%s+$", "")
    if line ~= "" and not line:match("^#") then
      local path = ROOT .. line:gsub("\\", "/")
      local chunk = assert(loadfile(path))
      chunk(ADDON, ns)
    end
  end
  return ns
end

-- tiny test framework
T = { passed = 0, failed = 0, failures = {} }
function T.Eq(a, b, what)
  if a ~= b then error(string.format("%s: expected %s, got %s", what or "value", tostring(b), tostring(a)), 2) end
end
function T.Ok(c, what) if not c then error((what or "condition") .. " failed", 2) end end
function T.Near(a, b, eps, what)
  if type(a) ~= "number" or math.abs(a - b) > (eps or 1e-9) then error(string.format("%s: expected ~%s, got %s", what or "value", tostring(b), tostring(a)), 2) end
end
function OUT(s) io.write(tostring(s), "\n") end
function T.Test(name, fn)
  local ok, err = pcall(fn)
  if ok then T.passed = T.passed + 1; OUT("  ok    " .. name)
  else T.failed = T.failed + 1; T.failures[#T.failures + 1] = name .. ": " .. tostring(err); OUT("  FAIL  " .. name .. ": " .. tostring(err)) end
end

-- (the mock replaces print: what the addon prints lands in PRINTS, test output goes through OUT)
dofile(ROOT .. "Tests/MockAPI.lua")
dofile(ROOT .. "Tests/FixtureTalents.lua")
dofile(ROOT .. "Tests/FixtureShaman42.lua")
for _, file in ipairs({ "CacheTests", "CompatTests", "ProfileTests", "ScannerTests", "EngineTests", "M4Tests", "M4bTests", "M4cTests" }) do
  OUT("== " .. file)
  assert(loadfile(ROOT .. "Tests/" .. file .. ".lua"))()
end
OUT(string.format("\n%d passed, %d failed", T.passed, T.failed))
if T.failed > 0 and os and os.exit then os.exit(1) end
