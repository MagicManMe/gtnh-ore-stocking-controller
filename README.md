# GTNH Ore-Stocking Controller (OpenComputers)

Keeps your **dust** stock topped up. Watches the processed-ore (dust) subnet;
when a dust drops below its `min`, it dumps the mapped ore(s) from the
unprocessed-ore subnet into the ore-processing subnet via ME Export Bus(es),
stopping once the dust recovers to `max`. Handles dusts that come from several
ores (e.g. Tin ← Tin Ore + Cassiterite) and prioritizes the neediest ores when
more dusts are low than you have export slots.

## Physical build

```
UNPROCESSED subnet ─cable─ [ME Export Bus] ─faces→ [ME Interface of PROCESSING subnet]
                                 │
                          [OC Adapter]                (controls the bus)

UNPROCESSED subnet ─ [ME Interface/Controller] ─ [OC Adapter]   (read ores + store descriptors)
DUST subnet        ─ [ME Interface/Controller] ─ [OC Adapter]   (read dust quantities)
```

Computer/server needs: CPU, at least T2/T3.5 RAM, an **HDD** with OpenOS, a
**Database upgrade** (Tier 3 = 81 slots, recommended for 30+ ores), a **GPU
(T3)** and a **screen** for the dashboard. Give export buses **capacity cards**
(more filter slots, up to 8) and **acceleration cards** (throughput).

Why export bus and not a transposer: your ores live in ME storage, and only an
export bus can pull arbitrary items out of an ME network. A transposer can only
move items between real inventories it physically touches.

## Install (get the files onto the OC computer)

Option A — pastebin: `pastebin get <code> main.lua` for each file.
Option B — floppy/drive: copy the four files into a directory on the OC HDD.
Option C — internet card: `wget <url> main.lua`.

Put `main.lua`, `config.lua`, and `list.lua` in the same directory.

## Setup

1. `lua list.lua` — prints component addresses and which side each export bus
   points. (Label your adapters in-game so you know which is dust vs ore.)
2. Edit `config.lua`:
   - Fill in `components` addresses (a unique prefix like `a1b2` is fine).
   - Fill in `exportBuses` (address + `side` + `slots`).
   - Fill in the `dusts` table: each dust's `min`/`max` and the ore(s) that
     produce it. **Verify exact in-game names and ore→dust recipes in NEI** —
     the examples are templates.
3. `lua main.lua` — starts the controller + dashboard. Ctrl+C stops it and
   clears all export slots so nothing keeps dumping.

## Notes

- Reads each subnet with a single `getItemsInNetwork()` per cycle (cheap
  because these are small dedicated subnets), so it avoids the well-known
  performance cost of many filtered calls on large networks.
- Item matching is by exact display label for readability; internally it stores
  descriptors by name+damage so it grabs the right item (not "Small Pile of …").
- `min`/`max` give hysteresis — a dust must climb back to `max` before its ores
  stop dumping, preventing rapid on/off flapping.
- If more ores need dumping than you have export slots, the lowest-priority ones
  wait and the dashboard shows a warning. Add another export bus to raise the
  ceiling.
