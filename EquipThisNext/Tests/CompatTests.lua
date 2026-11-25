-- The compatibility layer: missing functions, errors and hidden values never reach other code.
MOCK.Reset()
local ns = LoadAddon()
local Compat = ns.Compat

T.Test("a missing function reports 'missing' and records it", function()
  local ok, why = Compat.Call("C_Nope.DoesNotExist", 1)
  T.Eq(ok, false, "ok"); T.Eq(why, "missing", "why")
  T.Eq(Compat.status["C_Nope.DoesNotExist"].missing, 1, "recorded")
end)

T.Test("an erroring function is caught", function()
  local saved = GetDodgeChance
  GetDodgeChance = function() error("boom") end
  local ok, why, err = Compat.Call("GetDodgeChance")
  GetDodgeChance = saved
  T.Eq(ok, false, "ok"); T.Eq(why, "error", "why"); T.Ok(tostring(err):find("boom"), "message kept")
end)

T.Test("hidden values become the SECRET marker; Value says 'secret'", function()
  MOCK.statsSecret = true
  local ok, a, b = Compat.Call("UnitArmor", "player")
  T.Eq(ok, true, "call ok"); T.Eq(a, Compat.SECRET, "first return"); T.Eq(b, Compat.SECRET, "second return")
  local v, why = Compat.Value("GetCritChance")
  T.Eq(v, nil, "value"); T.Eq(why, "secret", "why")
  MOCK.statsSecret = false
  T.Eq(Compat.Value("GetCritChance"), 6.2, "readable again")
end)

T.Test("nested calls: C_Item.GetItemInfoInstant by link", function()
  local ok, id = Compat.Call("C_Item.GetItemInfoInstant", MOCK.WORN[1])
  T.Eq(ok, true, "ok"); T.Eq(id, 1001, "item id")
end)

T.Test("Field guards hidden tables and fields", function()
  T.Eq(Compat.Field(Compat.SECRET, "x"), nil, "secret table")
  T.Eq(Compat.Field({ x = MOCK.SECRET_VALUE }, "x"), nil, "secret field")
  T.Eq(Compat.Field({ x = 3 }, "x"), 3, "plain field")
end)

T.Test("every API we call is listed in KNOWN with a source", function()
  for path, src in pairs(Compat.KNOWN) do
    T.Ok(src == "docs" or src == "ui" or src == "eqt", path .. " source " .. tostring(src))
  end
end)
