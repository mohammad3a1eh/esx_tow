# ESX Towing Script

Realistic rope-based towing system for FiveM (ESX). Attach vehicles with a physical rope, tow them with snap physics, and watch bumpers rip off when you push it too far.

## Features

- **In-Vehicle Towing** — Select a vehicle to be towed, then connect from your tow truck.
- **On-Foot Manual Linking** — Link two vehicles while standing next to them (works on locked vehicles). Front/rear bumper auto-detected based on where you stand.
- **Dynamic Bumper Attachments** — Uses `GetModelDimensions` to attach the rope exactly to bumper centers, not generic `boot`/`engine` bones.
- **Realistic Snap Physics** — Rope snaps when:
  - The towed vehicle overtakes the tow truck (wrong direction)
  - Distance exceeds the limit (`maxDistance + 3.0`)
  - The tow vehicle throttles without moving for 20 seconds (stuck)
- **Mechanical Damage** — On snap, the target's front bumper detaches and falls to the road. If already missing, the tow truck's rear bumper falls off instead.

## Commands & Usage

### In-Vehicle Towing

1. Sit in the vehicle to be towed, run:
   ```
   /towin start
   ```
2. Switch to your tow truck (rear facing the target), run:
   ```
   /towin add
   ```
   Rope connects: tow truck rear bumper → target front bumper.
3. To disconnect cleanly (no damage):
   ```
   /towin end
   ```

### On-Foot Linking

No need to enter the vehicles — ideal for locked cars.

1. Stand near the **front or rear bumper** of the first vehicle, run:
   ```
   /towin link
   ```
   > First vehicle linked. Go to the second vehicle and type /towin link.
2. Walk to the second vehicle, stand near the bumper you want, run:
   ```
   /towin link
   ```
   Rope connects bumper-to-bumper. Pending link resets automatically after success.
3. To cancel a pending link while on foot:
   ```
   /towin end
   ```

## Requirements

- ESX (any recent version)
- [ox_lib](https://github.com/overextended/ox_lib)

## Config

```lua
local maxDistance = 12.0       -- rope length before snap check (+3.0 tolerance)
local stuckThreshold = 20000   -- ms of throttle-without-motion before snap
```
