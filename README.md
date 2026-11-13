# One Last Light — Graybox v0.1

A playable, editable 2D rescue and resource-management prototype for **Game Production and Management — WS 2026/27**.

**Engine:** Godot 4.7.2 Standard · **Language:** GDScript · **Target:** Windows x86_64 · **Renderer:** Compatibility · **Base viewport:** 1152 × 648.

All visuals use simple Godot drawing geometry. The source project needs no external assets, add-ons, online services, or runtime dependencies beyond Godot.

## Open and play

1. Install **Godot 4.7.2 Standard**, available from the [official archive](https://godotengine.org/download/archive/4.7.2-stable/). The .NET edition is unnecessary.
2. Extract `OneLastLight_Graybox_v0.1.zip`, preserving its folder structure.
3. In Godot Project Manager, choose **Import**, then select `OneLastLight/project.godot`.
4. Press **F5** to run the configured main scene. Alternatively, open `scenes/main.tscn` and press **F6**.
5. Launch a rescue from the introduction screen. Oxygen timers start when the round begins.

## Controls

| Input | Action |
| --- | --- |
| WASD / arrow keys | Move the boat with smooth acceleration and deceleration |
| E beside a discovered survivor | Pick up one survivor within the interaction ring |
| E inside the harbor safe zone | Deliver every passenger aboard |
| Esc | Pause / resume; oxygen and movement stop while paused |
| Mouse | Use introduction, pause, results, and upgrade buttons |

## Rescue loop

**Detect → Evaluate → Prioritize → Rescue → Return → Upgrade**

The central lighthouse automatically sweeps a visible yellow cone across the sea. Illumination discovers survivors and permanently marks their positions for the current round. Undiscovered survivors are only faintly visible. Each discovered contact shows its ID, remaining oxygen in seconds, and an oxygen bar; urgency changes its indicator color.

Ten survivors wait at different positions with individually configured oxygen durations. Their oxygen decreases even before discovery. Compare urgency and distance, navigate around the island and rocks, and press **E** within the boat's pickup radius. The initial boat holds **3 passengers**. Aboard survivors stop consuming oxygen, but contribute no rescue score until delivered.

Return to the green harbor zone on the right and press **E**. All passengers are delivered, capacity is freed, and each delivery earns **3 stars per survivor**. The HUD tracks passengers, delivered rescues, losses, active water contacts, stars, and contextual instructions. Messages report discoveries, pickups, a full boat, deliveries, oxygen losses, and the round result.

A round ends only when nobody remains active in the water **and** the boat has no passengers. If the final water contact is picked up, return to harbor to complete that rescue. If all remaining water contacts lose oxygen while passengers are aboard, those passengers still need delivery.

## Survivor states

| Code state | Meaning |
| --- | --- |
| `ACTIVE` | In the water; oxygen counts down; may be undiscovered or discovered |
| `RESCUED` | Picked up and aboard; oxygen stopped; not yet a successful delivery |
| `TRANSPORTED` | Delivered to harbor; included in the rescued counter and awarded stars |
| `LOST` | Oxygen reached zero in the water; cannot be picked up |

## Upgrades and subsequent rounds

Spend banked stars in the results menu between rounds. Upgrades cannot be purchased during an active rescue.

| Upgrade | Effect per level | Levels | Costs |
| --- | --- | --- | --- |
| Capacity | +1 passenger; 3 seats initially, 6 at maximum | 3 | 6, 9, 12 stars |
| Speed | +18% of base speed; +54% at maximum | 3 | 6, 9, 12 stars |

**Next Round** increases the round number and launches another rescue. **Retry** restarts the current round number. Both reset survivor states, discovery, oxygen, the boat's position, and round statistics while preserving banked currency and purchased upgrades. They reuse the same map and oxygen durations to support repeatable playtests. Currency and upgrades persist for the current application session only; there is no save file.

## Project structure and tuning

`scenes/main.tscn` is the complete editable level. The boat, survivor, lighthouse, harbor, and rock are reusable scenes in `scenes/`. Their matching scripts own entity behavior, `scripts/game_manager.gd` owns round state and the economy, and `scripts/main.gd` connects the level and interface.

`screenshots/` contains actual Godot captures of the briefing, gameplay, pause, debrief, and a purchased upgrade. `tests/` contains the repeatable runtime suite and its recorded output. `tools/package_project.py` rebuilds the source archive without engine caches.

Gameplay parameters use exported variables and can be changed in the Inspector or script defaults:

| Parameter | Default | Location |
| --- | --- | --- |
| Survivor positions / individual oxygen durations | Ten authored contacts with different timers | Survivor instances in `scenes/main.tscn`; `survivor.gd` exports `oxygen_duration`, `survivor_id` |
| Boat base speed | 185 px/s | `scripts/player_boat.gd`: `base_speed` |
| Acceleration / deceleration | 530 / 430 px/s² | `scripts/player_boat.gd` |
| Pickup radius | 48 px | `scripts/player_boat.gd`: `pickup_radius` |
| Starting capacity / speed bonus | 3 / 0.18 per level | `scripts/player_boat.gd` |
| Stars per delivery | 3 per survivor | `scripts/game_manager.gd`: `stars_per_survivor` |
| Upgrade base costs / cost step / maximum level | 6 / 3 / 3 | `scripts/game_manager.gd` |
| Boat starting position | Near harbor | `scripts/game_manager.gd`: `boat_spawn` |
| Lighthouse rotation / range / cone width | 0.50 rad/s / 660 px / 0.48 rad | `scripts/lighthouse.gd` |
| Harbor safe radius | 62 px | `scripts/harbor.gd`: `safe_radius` |
| Rocks, island, and survivor layout | Authored graybox level | `scenes/main.tscn` and reusable obstacle scenes |

Physics layer 1 contains navigation obstacles; the boat occupies layer 2 and collides with layer 1. The harbor is a nonblocking interaction zone. Fog and storm markings are visual route-planning placeholders; they do not change boat handling or oxygen.

## Windows build

The project includes a **Windows Desktop** export preset configured for **x86_64** with the PCK embedded in the executable.

1. In Godot 4.7.2, use **Editor → Manage Export Templates** to install the matching **4.7.2 Standard export templates**.
2. Open **Project → Export**, select **Windows Desktop**, and export the project to `builds/OneLastLight.exe` or another location.
3. Copy the exported executable to a Windows x86_64 computer to play without the editor.

The delivery ZIP is the editable source project. See `TESTING.md` for whether an executable export and Windows runtime were validated in the delivery environment.

## Verification

Actual validation results and environment limitations are recorded in **`TESTING.md`**. To repeat the automated checks from this project directory, replace `godot` below with the path to your Godot 4.7.2 executable if necessary:

```sh
godot --headless --path . --editor --quit
godot --headless --path . --script res://tests/runtime_suite.gd
```

For a manual playtest, check movement and deceleration in all directions, collisions with rocks and the central island, beam discovery, oxygen countdown and loss, pickups up to capacity, rejection when full, and delivery with **E** at harbor. Confirm that pickups alone do not increase successful rescues or stars. Complete a round, buy both upgrade types, and verify their effect after retrying or proceeding. Pause during a countdown to confirm that oxygen freezes, then resume.

## Known scope limits

- This is one graybox test level, with provisional tuning and a reusable round rather than a six-level campaign.
- Weather zones provide visual navigation context only. There is no advanced weather simulation or beam occlusion by rocks.
- All graphics are simple drawn shapes; there are no external sprites, detailed boat animations, or audio assets.
- No multiplayer, complex AI pathfinding, helicopter, Panic Meter, backend, payments, or save system is included.
- Headless checks cannot establish visual readability, keyboard feel, or native Windows behavior; use the manual playtest alongside the recorded automated results.

## Future Work

Later iterations may add a **second emergency rescue boat that independently rescues a limited number of survivors**. It is intentionally not implemented in v0.1. Other possible work includes balancing oxygen and travel times through playtests, weather mechanics, accessibility settings, audio feedback, persistent progression, and additional authored levels.
