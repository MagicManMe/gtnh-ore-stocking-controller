-- main.lua -----------------------------------------------------------------
-- GTNH ore-stocking controller for OpenComputers.
--
-- Watches dust quantities on the processed-ore (dust) subnet. When a dust
-- falls below its `min`, it dumps the mapped ore(s) from the unprocessed-ore
-- subnet into the processing subnet via ME Export Bus(es), stopping once the
-- dust recovers to `max`. With more dusts low than there are export slots,
-- the neediest ores win (priority queue) and rotate as dusts recover.
--
-- Run:  lua main.lua        (Ctrl+C or Alt+... to stop; buses are cleared)
-----------------------------------------------------------------------------

local component = require("component")
local computer  = require("computer")
local event     = require("event")
local os        = require("os")
local config    = require("config")

-----------------------------------------------------------------------------
-- Component resolution
-----------------------------------------------------------------------------

local function resolve(addr, kind)
  if not addr then return nil end
  local full = component.get(addr)          -- expand a unique prefix
  if not full then
    error(("No component matches address %q (%s). Run list.lua."):format(addr, kind or "?"))
  end
  return component.proxy(full)
end

local dustNet  = resolve(config.components.dustNet,  "dustNet")
local oreNet   = resolve(config.components.oreNet,   "oreNet")
local database = resolve(config.components.database, "database")

local buses = {}
for i, b in ipairs(config.exportBuses) do
  buses[i] = { proxy = resolve(b.address, "exportBus#" .. i), side = b.side, slots = b.slots }
end

-- GPU / screen for the dashboard
local gpu = component.gpu
if config.components.screen then gpu.bind(component.get(config.components.screen)) end
local COLS, ROWS = gpu.maxResolution()
gpu.setResolution(COLS, ROWS)

-----------------------------------------------------------------------------
-- Small helpers
-----------------------------------------------------------------------------

local COLOR = { bg=0x0F0F0F, header=0x66CCFF, ok=0x33CC33, warn=0xFFCC00,
                crit=0xFF3333, dim=0x888888, text=0xFFFFFF, active=0xFF9933 }

-- Query a subnet once and return label -> {name, damage, size, label} (summed).
local function snapshot(net)
  local ok, items = pcall(function() return net.getItemsInNetwork() end)
  if not ok or type(items) ~= "table" then
    return nil, tostring(items)
  end
  local byLabel = {}
  for _, it in ipairs(items) do
    local lbl = it.label
    if lbl then
      local e = byLabel[lbl]
      if e then
        e.size = e.size + (it.size or 0)
        e.stacks = e.stacks + 1
      else
        byLabel[lbl] = { name = it.name, damage = it.damage, size = it.size or 0,
                         label = lbl, stacks = 1 }
      end
    end
  end
  return byLabel
end

-----------------------------------------------------------------------------
-- Database allocation: each ore we ever export gets one persistent DB slot,
-- filled lazily the first time we see that ore in the ore subnet.
-----------------------------------------------------------------------------

local dbCapacity = database.size and database.size() or 81
local oreDbSlot  = {}   -- oreLabel -> db slot number
local nextDbSlot = 1

-- Ensure `oreLabel` has a descriptor stored in the DB. Returns db slot or nil.
local function ensureDbEntry(oreLabel, oreStack)
  local slot = oreDbSlot[oreLabel]
  if slot then return slot end
  if nextDbSlot > dbCapacity then
    return nil, "database full (" .. dbCapacity .. " slots) - need a bigger DB or fewer ores"
  end
  slot = nextDbSlot
  -- Store the exact stack (name+damage) so we grab the right item, not a
  -- similarly-named one (e.g. "Small Pile of ...").
  local ok, res = pcall(function()
    return oreNet.store({ name = oreStack.name, damage = oreStack.damage },
                        database.address, slot)
  end)
  if not ok or not res then
    return nil, "store() failed for " .. oreLabel .. ": " .. tostring(res)
  end
  oreDbSlot[oreLabel] = slot
  nextDbSlot = nextDbSlot + 1
  return slot
end

-----------------------------------------------------------------------------
-- Export bus slot pool. We treat every slot on every bus as one flat pool
-- and diff desired-vs-current each cycle so we only rewrite what changed.
-----------------------------------------------------------------------------

local pool = {}   -- flat list of { bus=<busIdx>, slot=<n>, current=<oreLabel|nil> }
for bi, b in ipairs(buses) do
  for s = 1, b.slots do
    pool[#pool + 1] = { bus = bi, slot = s, current = nil }
  end
end

local function setSlot(cell, oreLabel, dbSlot)
  local b = buses[cell.bus]
  local ok, err = pcall(function()
    if oreLabel then
      b.proxy.setExportConfiguration(b.side, cell.slot, database.address, dbSlot)
    else
      b.proxy.setExportConfiguration(b.side, cell.slot)   -- clear
    end
  end)
  if ok then
    cell.current = oreLabel
  end
  return ok, err
end

-----------------------------------------------------------------------------
-- Core cycle logic
-----------------------------------------------------------------------------

-- Per-dust active flag for hysteresis (dumping between min and max).
local dustActive = {}

-- Returns:
--   rows    : dashboard rows (dust status)
--   desired : ordered list of { ore=<label>, stack=<oreStack>, urgency=<0..1> }
local function computeDesired(dustSnap, oreSnap)
  local rows = {}
  local oreNeed = {}     -- oreLabel -> { urgency, stack }
  local order = {}       -- keeps first-seen order of ores

  for _, d in ipairs(config.dusts) do
    local have = (dustSnap[d.dust] and dustSnap[d.dust].size) or 0

    -- hysteresis state machine
    if have < d.min then
      dustActive[d.dust] = true
    elseif have >= d.max then
      dustActive[d.dust] = false
    end
    local active = dustActive[d.dust] or false

    -- urgency 0..1 (how empty it is relative to min); higher = more urgent
    local urgency = 0
    if d.min > 0 then urgency = math.max(0, math.min(1, (d.min - have) / d.min)) end

    local dumping = {}
    if active then
      for _, oreLabel in ipairs(d.ores) do
        local st = oreSnap[oreLabel]
        if st and st.size > 0 then
          dumping[#dumping + 1] = oreLabel
          local cur = oreNeed[oreLabel]
          if cur then
            cur.urgency = math.max(cur.urgency, urgency)
          else
            oreNeed[oreLabel] = { urgency = urgency, stack = st }
            order[#order + 1] = oreLabel
          end
        end
      end
    end

    rows[#rows + 1] = { dust = d.dust, have = have, min = d.min, max = d.max,
                        active = active, dumping = dumping,
                        oresConfigured = d.ores }
  end

  -- Build ordered desired list, most urgent first (stable on ties).
  local desired = {}
  for _, lbl in ipairs(order) do
    desired[#desired + 1] = { ore = lbl, stack = oreNeed[lbl].stack,
                              urgency = oreNeed[lbl].urgency }
  end
  table.sort(desired, function(a, b)
    if a.urgency ~= b.urgency then return a.urgency > b.urgency end
    return a.ore < b.ore
  end)

  return rows, desired
end

-- Assign the desired ores to the slot pool, clearing everything not desired.
-- Returns list of warnings.
local function applyToBuses(desired)
  local warnings = {}
  local wanted = {}                     -- oreLabel -> true (top N that fit)
  local capacity = #pool
  for i = 1, math.min(capacity, #desired) do wanted[desired[i].ore] = desired[i] end

  if #desired > capacity then
    warnings[#warnings + 1] = ("%d ores need dumping but only %d export slots - lowest-priority %d waiting")
      :format(#desired, capacity, #desired - capacity)
  end

  -- 1) Clear slots whose current ore is no longer wanted.
  for _, cell in ipairs(pool) do
    if cell.current and not wanted[cell.current] then
      setSlot(cell, nil)
    end
  end

  -- 2) Which wanted ores are already assigned to a slot?
  local assigned = {}
  for _, cell in ipairs(pool) do
    if cell.current and wanted[cell.current] then assigned[cell.current] = true end
  end

  -- 3) Place remaining wanted ores into free slots.
  local free = {}
  for _, cell in ipairs(pool) do
    if not cell.current then free[#free + 1] = cell end
  end
  local fi = 1
  for _, item in ipairs(desired) do
    if wanted[item.ore] and not assigned[item.ore] then
      local cell = free[fi]
      if not cell then break end
      local dbSlot, err = ensureDbEntry(item.ore, item.stack)
      if dbSlot then
        local ok, serr = setSlot(cell, item.ore, dbSlot)
        if ok then assigned[item.ore] = true; fi = fi + 1
        else warnings[#warnings + 1] = tostring(serr) end
      else
        warnings[#warnings + 1] = tostring(err)
      end
    end
  end

  return warnings
end

-----------------------------------------------------------------------------
-- Dashboard
-----------------------------------------------------------------------------

local function fmt(n)
  if n >= 1e6 then return string.format("%.2fM", n / 1e6) end
  if n >= 1e3 then return string.format("%.1fk", n / 1e3) end
  return tostring(n)
end

local function pad(s, w)
  s = tostring(s)
  if #s > w then return s:sub(1, w - 1) .. "\xE2\x80\xA6" end
  return s .. string.rep(" ", w - #s)
end

local cycle = 0
local function draw(rows, desired, warnings, err)
  cycle = cycle + 1
  gpu.setBackground(COLOR.bg)
  gpu.setForeground(COLOR.text)
  gpu.fill(1, 1, COLS, ROWS, " ")

  gpu.setForeground(COLOR.header)
  gpu.set(2, 1, "GTNH Ore Stocking Controller")
  gpu.setForeground(COLOR.dim)
  local slotsUsed = 0
  for _, c in ipairs(pool) do if c.current then slotsUsed = slotsUsed + 1 end end
  gpu.set(2, 2, ("cycle %d   export slots %d/%d used   poll %ds")
    :format(cycle, slotsUsed, #pool, config.pollInterval))

  if err then
    gpu.setForeground(COLOR.crit)
    gpu.set(2, 4, "READ ERROR: " .. err)
    return
  end

  -- header row
  local y = 4
  gpu.setForeground(COLOR.header)
  gpu.set(2, y, pad("DUST", 22) .. pad("HAVE", 9) .. pad("MIN", 8) .. pad("STATUS", 10) .. "DUMPING")
  y = y + 1
  gpu.setForeground(COLOR.dim)
  gpu.set(2, y, string.rep("\xE2\x94\x80", COLS - 2))
  y = y + 1

  for _, r in ipairs(rows) do
    if y >= ROWS then break end
    local status, col
    if r.active then status, col = "DUMPING", COLOR.active
    elseif r.have < r.min then status, col = "LOW", COLOR.warn
    else status, col = "OK", COLOR.ok end

    gpu.setForeground(r.have < r.min and COLOR.warn or COLOR.text)
    gpu.set(2, y, pad(r.dust, 22) .. pad(fmt(r.have), 9) .. pad(fmt(r.min), 8))
    gpu.setForeground(col)
    gpu.set(2 + 22 + 9 + 8, y, pad(status, 10))
    gpu.setForeground(COLOR.dim)
    gpu.set(2 + 22 + 9 + 8 + 10, y, pad(table.concat(r.dumping, ", "), COLS - 2 - 49))
    y = y + 1
  end

  -- warnings
  if #warnings > 0 and y < ROWS then
    y = y + 1
    gpu.setForeground(COLOR.warn)
    for _, w in ipairs(warnings) do
      if y >= ROWS then break end
      gpu.set(2, y, "! " .. pad(w, COLS - 4))
      y = y + 1
    end
  end
end

-----------------------------------------------------------------------------
-- Main loop
-----------------------------------------------------------------------------

local function clearAllBuses()
  for _, cell in ipairs(pool) do
    if cell.current then setSlot(cell, nil) end
  end
end

local function tick()
  local dustSnap, derr = snapshot(dustNet)
  if not dustSnap then draw({}, {}, {}, "dust subnet: " .. derr); return end
  local oreSnap, oerr = snapshot(oreNet)
  if not oreSnap then draw({}, {}, {}, "ore subnet: " .. oerr); return end

  local rows, desired = computeDesired(dustSnap, oreSnap)
  local warnings = applyToBuses(desired)
  draw(rows, desired, warnings, nil)
end

print("Ore stocking controller starting. Press Ctrl+C to stop.")
local running = true
-- Clean shutdown on interrupt: clear buses so nothing keeps dumping.
event.listen("interrupted", function() running = false; return false end)

local ok, loopErr = pcall(function()
  while running do
    local tok, terr = pcall(tick)
    if not tok then
      gpu.setForeground(COLOR.crit)
      gpu.set(2, ROWS, "TICK ERROR: " .. tostring(terr))
    end
    -- interruptible sleep
    local deadline = computer.uptime() + config.pollInterval
    while running and computer.uptime() < deadline do
      os.sleep(0.2)
    end
  end
end)

clearAllBuses()
gpu.setForeground(COLOR.text)
gpu.set(2, ROWS, "Stopped. All export slots cleared.        ")
if not ok then print("Fatal: " .. tostring(loopErr)) end
