-- config.lua ---------------------------------------------------------------
-- Configuration for the GTNH ore-stocking controller.
--
-- Everything the program needs to be told about YOUR base lives here.
-- Edit this file, not main.lua.
--
-- To find the addresses / sides, run:  lua list.lua
-----------------------------------------------------------------------------

local config = {}

-- === Component addresses ===================================================
-- Full or unique-prefix addresses are fine (e.g. "a1b2" if unambiguous).
-- Each must be an OC Adapter placed against the relevant block.
config.components = {
  -- ME Interface/Controller on the DUST (processed-ore) subnet. Read-only here.
  dustNet   = "PUT-DUST-SUBNET-ADAPTER-ADDRESS",

  -- ME Interface/Controller on the UNPROCESSED-ore subnet.
  -- Used to read what ores are available AND to store() their descriptors.
  oreNet    = "PUT-ORE-SUBNET-ADAPTER-ADDRESS",

  -- OC Database upgrade. Holds item descriptors that export buses point at.
  -- Tier 1 = 9 slots, Tier 2 = 25, Tier 3 = 81. Use T3 for 30+ ores.
  database  = "PUT-DATABASE-ADDRESS",

  -- Optional. Screen address for the dashboard. Leave nil to use the
  -- primary bound screen.
  screen    = nil,
}

-- === Export buses ==========================================================
-- One entry per ME Export Bus. Each bus lives on the UNPROCESSED subnet and
-- its output face pushes into the PROCESSING subnet's input (an ME Interface).
--
--   address = the OC Adapter touching that export bus
--   side    = the numeric side the bus points (0=down,1=up,2=north,3=south,
--             4=west,5=east). `list.lua` prints which sides have a bus.
--   slots   = filter slots on that bus (1 base, +capacity cards, max 8)
--
-- Add more buses to raise how many ores can dump SIMULTANEOUSLY.
config.exportBuses = {
  { address = "PUT-EXPORT-BUS-ADAPTER-ADDRESS", side = 1, slots = 8 },
  -- { address = "PUT-SECOND-EXPORT-BUS-ADDRESS", side = 1, slots = 8 },
  -- { address = "PUT-THIRD-EXPORT-BUS-ADDRESS",  side = 1, slots = 8 },
}

-- === Timing ================================================================
config.pollInterval = 5      -- seconds between checks (keep >=3 to be nice to the server)

-- === Burst / cooldown (anti-overshoot) =====================================
-- Dumped ore must be PROCESSED before the dust count rises, so left running
-- the controller would keep dumping and massively overshoot. Instead each ore
-- dumps in short bursts with a rest between them:
--
--   dumpBurst    = seconds to dump an ore before pausing it. Effective minimum
--                  is one pollInterval, so keep it >= pollInterval.
--   dumpCooldown = seconds to pause that ore afterwards, giving processing time
--                  to convert the backlog and raise the dust. After it expires,
--                  if the dust is still low the ore dumps again.
--
-- Longer cooldown = gentler / less overshoot but slower to refill. Tune to how
-- fast your ore processing keeps up.
config.dumpBurst    = 10
config.dumpCooldown = 60

-- === The dust -> ore mapping ===============================================
-- One row per DUST you want to keep stocked.
--
--   dust  = exact display name of the dust (as shown in NEI / AE terminal)
--   min   = start dumping ores when the dust count drops BELOW this
--   max   = stop dumping once the dust count reaches/exceeds this
--           (min/max give hysteresis so it doesn't flap on/off constantly)
--   ores  = list of ore display names to dump when this dust is low.
--           Most are 1:1; list several when a dust comes from multiple ores.
--
-- Names are matched EXACTLY against the item's display label. If a name is
-- ambiguous (matches more than one stack) the program warns you.
--
-- The examples below are TEMPLATES — verify the exact in-game names and which
-- ores yield which dust in YOUR pack version via NEI (they occasionally
-- change). Add the rest of your ~30+ dusts following the same shape.
config.dusts = {
  -- 1:1 examples
  { dust = "Titanium Dust",   min = 5000,  max = 10000, ores = { "Titanium Ore" } },
  { dust = "Aluminium Dust",  min = 5000,  max = 10000, ores = { "Bauxite Ore", "Aluminium Ore" } },
  { dust = "Redstone",        min = 20000, max = 40000, ores = { "Redstone Ore" } },

  -- Multi-ore -> one dust examples (the case you called out)
  { dust = "Tin Dust",        min = 5000,  max = 10000, ores = { "Tin Ore", "Cassiterite Ore" } },
  { dust = "Copper Dust",     min = 5000,  max = 10000, ores = { "Copper Ore", "Chalcopyrite Ore", "Tetrahedrite Ore", "Malachite Ore" } },
  { dust = "Iron Dust",       min = 5000,  max = 10000, ores = { "Iron Ore", "Magnetite Ore", "Pyrite Ore", "Brown Limonite Ore", "Yellow Limonite Ore", "Banded Iron Ore" } },
  { dust = "Nickel Dust",     min = 3000,  max = 6000,  ores = { "Nickel Ore", "Garnierite Ore", "Pentlandite Ore" } },
  { dust = "Zinc Dust",       min = 3000,  max = 6000,  ores = { "Zinc Ore", "Sphalerite Ore" } },
  { dust = "Lead Dust",       min = 3000,  max = 6000,  ores = { "Lead Ore", "Galena Ore" } },

  -- ... add the rest here ...
}

return config
