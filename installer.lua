-- installer.lua ------------------------------------------------------------
-- One-shot installer for the GTNH ore-stocking controller.
-- Requires an Internet Card in the computer.
--
-- On the OC computer, run:
--   wget https://raw.githubusercontent.com/MagicManMe/gtnh-ore-stocking-controller/main/installer.lua
--   installer
--
-- Downloads main.lua and list.lua (overwriting), and config.lua ONLY if you
-- don't already have one, so your edits are never clobbered.
-----------------------------------------------------------------------------

local shell = require("shell")
local fs    = require("filesystem")

local BASE = "https://raw.githubusercontent.com/MagicManMe/gtnh-ore-stocking-controller/main/"

-- name -> overwrite?  (config.lua is preserved if present)
local files = {
  { name = "main.lua", overwrite = true  },
  { name = "list.lua", overwrite = true  },
  { name = "config.lua", overwrite = false },
}

if not require("component").isAvailable("internet") then
  io.stderr:write("No Internet Card found. Install one, then re-run.\n")
  return
end

print("Installing ore-stocking controller from GitHub...\n")

local failed = false
for _, f in ipairs(files) do
  if (not f.overwrite) and fs.exists(f.name) then
    print(("  skip   %s  (already exists, keeping your copy)"):format(f.name))
  else
    io.write(("  fetch  %s ... "):format(f.name))
    -- wget -fq: force overwrite, quiet
    local ok = shell.execute("wget -fq " .. BASE .. f.name .. " " .. f.name)
    if ok and fs.exists(f.name) then
      print("ok")
    else
      print("FAILED")
      failed = true
    end
  end
end

print("")
if failed then
  print("Some files failed to download. Check the Internet Card / URL and retry.")
else
  print("Done. Next steps:")
  print("  1) lua list.lua        -- find your component addresses + bus sides")
  print("  2) edit config.lua     -- addresses, buses, and your dust->ore table")
  print("  3) lua main.lua        -- start the controller")
end
