-- Cache and fingerprints (pure Lua).
MOCK.Reset()
local ns = LoadAddon()
local Cache = ns.Cache

T.Test("set / get / fingerprint mismatch", function()
  Cache.Set("profile", "me", "A", "fp1")
  T.Eq(Cache.Get("profile", "me", "fp1"), "A", "same fingerprint")
  T.Eq(Cache.Get("profile", "me", "fp2"), nil, "other fingerprint")
  T.Eq(Cache.Get("profile", "me"), "A", "no fingerprint asked")
end)

T.Test("invalidate a kind leaves the others", function()
  Cache.Set("item", "x", 1); Cache.Set("talents", "active", 2)
  local gen = Cache.generation.item
  Cache.Invalidate("item")
  T.Eq(Cache.Get("item", "x"), nil, "item gone")
  T.Eq(Cache.Get("talents", "active"), 2, "talents kept")
  T.Eq(Cache.generation.item, gen + 1, "generation bumped")
end)

T.Test("fingerprint is order-independent and type-aware", function()
  local a = Cache.Fingerprint({ b = 2, a = 1, list = { 3, 4 } })
  local b = Cache.Fingerprint({ list = { 3, 4 }, a = 1, b = 2 })
  T.Eq(a, b, "same table, different insertion order")
  T.Ok(Cache.Fingerprint({ a = 1 }) ~= Cache.Fingerprint({ a = "1" }), "number vs text differ")
  T.Ok(Cache.Fingerprint({ 1, 2 }) ~= Cache.Fingerprint({ 2, 1 }), "list order matters")
end)
