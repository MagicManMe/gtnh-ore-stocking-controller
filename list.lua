-- list.lua -----------------------------------------------------------------
-- Discovery helper. Prints component addresses you need for config.lua, and
-- probes each ME Export Bus to tell you which SIDE its bus points.
--
-- Run:  lua list.lua
-----------------------------------------------------------------------------

local component = require("component")
local sides     = require("sides")

local function section(title) print("\n=== " .. title .. " ===") end

section("All AE2 network components (me_interface / me_controller)")
print("Map these to dustNet / oreNet by checking which subnet each Adapter")
print("touches (label your adapters in-game to keep them straight):")
for addr, kind in component.list() do
  if kind == "me_interface" or kind == "me_controller" then
    print(("  %s  [%s]"):format(addr, kind))
  end
end

section("Databases")
for addr in component.list("database") do
  local db = component.proxy(addr)
  local size = db.size and db.size() or "?"
  print(("  %s  (%s slots)"):format(addr, tostring(size)))
end

section("Export buses + which side each has a bus")
for addr in component.list("me_exportbus") do
  print("  " .. addr)
  local bus = component.proxy(addr)
  for name, s in pairs({ down=sides.down, up=sides.up, north=sides.north,
                         south=sides.south, west=sides.west, east=sides.east }) do
    local ok, cfg = pcall(function() return bus.getExportConfiguration(s) end)
    if ok and cfg ~= nil then
      print(("      side %d (%s) has a bus"):format(s, name))
    end
  end
end

section("Screens")
for addr in component.list("screen") do print("  " .. addr) end

print("\nCopy the relevant addresses into config.lua. A unique prefix works,")
print("e.g. the first 3-4 characters, as long as it's unambiguous.")
