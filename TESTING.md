# Verification — One Last Light v0.2

Tested on Windows on 13 November 2026 with Godot 4.7.2 Standard, `4.7.2.stable.official.ed1daf0bf`. The v0.1 tag at `e4a78ab` passed its original **57/57** checks when independently extracted and executed on this machine.

## Reproduce

From the project directory, replace `godot` with your Godot 4.7.2 console executable if needed. On Windows, prefix a quoted executable path with the PowerShell invocation operator `&`.

```sh
godot --headless --path . --editor --import
godot --headless --path . --quit-after 30
godot --headless --path . --fixed-fps 60 --script res://tests/runtime_suite.gd
godot --headless --path . --fixed-fps 60 --script res://tests/tutorial_suite.gd
godot --headless --path . --fixed-fps 60 --script res://tests/intro_suite.gd
godot --headless --path . --fixed-fps 60 --script res://tests/hud_suite.gd
godot --headless --path . --fixed-fps 60 --script res://tests/balance_route.gd
```

The editor import and main-scene startup completed with exit code 0. The expanded runtime suite passed **109/109 checks**, exit code 0. The three balance scenarios also completed with exit code 0. The engine reported no script or resource errors in these runs. The full runtime output is in [tests/runtime_suite.log](tests/runtime_suite.log).

## Gameplay coverage

| Area | What the runtime suite exercised |
| --- | --- |
| Launch and level | Configured main scene, 15 unique IDs, positions and oxygen budgets, both boats at harbor, starting seats, 240-second timer, oxygen held during briefing |
| Lighthouse | Gradual turn toward the cursor, stable aim at rest, range and cone exclusion, temporary visibility through 2.95 seconds, hidden after 3.01 seconds, immediate rediscovery |
| Main boat | Input acceleration and deceleration, sustained collision with a real rock, blocking island shape, in-range E before any discovery tick, proximity reveal, full boat rejection |
| Oxygen and scoring | Immediate oxygen freeze on either boat, no rescue credit before delivery, automatic or manual unloading, 3 stars per personal delivery, existing star balance preserved by emergency rescue |
| Emergency navigation | Right-click, invalid and duplicate assignments, independent motion, swept hull clearance around rocks and island on both legs, remembered target after fade, automatic return if the player intercepts a target or its oxygen expires |
| Availability and pause | All five boat states, cooldown rejection and recovery, Esc freezes level time, oxygen, both boats, lighthouse and cooldown, resume continues the assignment |
| Outcomes and HUD | Separate death and timeout screens, third loss ends the round immediately, countdown expiration with passengers aboard, 13 deliveries with 2 losses, all 15 delivered, final passenger on each boat, HUD totals and cooldown display |
| Economy and replay | Results-screen purchase, insufficient funds, increasing prices, maximum rank, actual higher top speed under input, session bank retained, clean replay of Level 1 |

The suite uses real input events, game signals, colliders, states and HUD labels. Some transition tests position the player directly or advance a timer to a boundary. A separate reachability check sent the emergency boat to each of the 15 authored contacts and back individually. Twelve trips required obstacle waypoints. Sampling hull clearance against the static shapes at each physics tick found zero penetrations. Individual round trips took 4.52–25.70 seconds before cooldown.

## Unupgraded Level 1 routes

The balance script loads a fresh level for each run, steers the main boat with movement actions, and sails around the authored obstacles using the starting equipment. It uses the actual oxygen timers, visibility updates, emergency AI, pickup distance and harbor interactions. The scripted pilot knows the map and aims at known coordinates. All routes include a four-second initial survey, a decision delay per trip and 0.8 seconds of sighting per active contact on the main boat's route. The clock continues throughout.

| Route | Decision time per trip | Main delivered | Emergency delivered | Lost | Stars | Elapsed | Smallest oxygen reserve at pickup |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Mixed fleet | 3 s | 14 | 1 | 0 | 42 | 129.88 s | 9.32 s |
| Main boat only | 3 s | 14 | 0 | 1 | 42 | 153.78 s | 1.58 s |
| Main boat only, faster decisions | 1 s | 15 | 0 | 0 | 45 | 137.78 s | 3.95 s |

The mixed route assigns the distant northwest contact (#06, 26 seconds of oxygen) to the emergency boat at launch. The player takes the eastern pair #01 and #10 first and uses seven two-seat trips. The solo routes start with the northwest pair #06 and #12. With three seconds of decision time, the solo boat loses one person even though it finishes well inside the global deadline. Sending the emergency boat saves that life for the same 42 stars. A quicker solo pilot can earn all 45. These runs establish the feasibility of the routes and illustrate where oxygen, travel and the second seat affect the decision.

## Rendered review

The game also ran under the Windows Compatibility renderer on an NVIDIA GeForce RTX 5070 Laptop GPU (OpenGL 3.3). At 1152 × 648, the briefing, gameplay, pause, victory, both failure messages and the purchased-upgrade screen were inspected for text fit, HUD readability and dispatch feedback. The five current captures in `screenshots/` cover briefing, gameplay, pause, debrief and upgrade. The debrief and upgrade captures use scripted deliveries for screen inspection.

## Remaining human playtests

1. Give a new player the briefing and a fresh bank. Record the first three attempts with 0 upgrades. Collect delivery totals per boat, first loss time, unused time and where collisions delayed a pickup.
2. Ask the player to compare nearby oxygen readings while steering around a rock, then dispatch to a distant visible contact. Check whether they understand fading contacts, the proximity ring, the assignment brackets and the cooldown.
3. Compare two attempts using the same chart, one with the emergency boat and one without it. Ask why the player sent the boat or kept the three-star delivery. Record whether at least 13 people reach harbor and how much search time was spent finding the first urgent contact.
4. Inspect oxygen numbers and red/yellow/green bars at the target display scale. Try simultaneous mouse aim, WASD and E on a physical keyboard. Replay after buying speed and check whether the handling change is perceptible.

The reference pilot's foreknowledge leaves human search time, steering difficulty and perceived fairness unmeasured. Balancing should use observed player routes before changing the four-minute deadline. Native Windows editor/runtime testing is complete at the base viewport. Standalone executable export and additional display sizes remain unverified. Only Level 1 and the main speed shop are playable.

## Tutorial (`feature/step-by-step-tutorial`)

The single briefing page was replaced by a four-step tutorial (Your Mission, Find Survivors, Rescue & Deliver, Emergency Rescue) with Next and Back, a "Step n of 4" counter, four progress segments and Launch Rescue on the last page only. `tests/tutorial_suite.gd` checks each page's text, navigation limits, progress state, button set, layout fit at 1152 × 648, a frozen 4:00 timer and full oxygen tanks while it is open, stray E, Esc, right-click and movement input, a launch that happens exactly once, and pause, results, upgrade and replay after launching from the tutorial. Replay does not reopen it.

Verified on Linux with the official Godot 4.7.2 build, not on the Windows machine used for the v0.2 numbers above:

| Run | Result |
| --- | --- |
| `runtime_suite.gd`, unchanged | 109/109 |
| `tutorial_suite.gd`, `--headless` (button signals stand in for mouse clicks) | 172/172 |
| `tutorial_suite.gd`, windowed under Xvfb (real mouse click events) | 172/172 |
| `balance_route.gd` | Identical to the table above |
| Web export (single-threaded) in headless Chromium with software WebGL | Clicked through all four pages, Back and Next, stray keys, then Launch Rescue. The clock ran and survivors were revealed. |

The bundled UI font has no arrow glyphs and Web builds have no system fonts, so `←` and `→` render as missing-glyph boxes there. The tutorial draws its arrows from an inline SVG and a test asserts every tutorial character exists in the bundled font. The existing speed-shop button still contains `→` and was not changed.

Not verified: a Windows desktop run, Firefox or Safari, a GPU renderer, and display sizes other than 1152 × 648. `screenshots/briefing.png` still shows the old single-page briefing.

## Level-start countdown (`feature/level-start-countdown`)

Launch Rescue and Replay Level 1 now prepare the round, play a 3-second 3 → 2 → 1 countdown with a brief GO!, and only then activate gameplay. `GameManager` was split into `prepare_round()` (reset everything, boats at their berths, beam on the harbor, every gameplay system stopped) and `begin_round()` (switch boat controls, lighthouse aiming, emergency dispatch, the clock and oxygen on together); `start_round()` and `restart_round()` still do both, so the earlier suites are unchanged. The white boat follows a cubic Bézier path from above the top edge of the chart into its berth, driven by one delta-accumulated clock, so number, boat and overlay stay in step at any frame rate. The tutorial code was not touched.

`tests/intro_suite.gd` (132 checks) covers: 3, 2, 1 order and roughly one second each; a large centred number with no backdrop; boat above the visible sea at t = 0, entering within the first second, moving only downward with no jumps or sharp bends, facing its direction of travel while moving, a seamless hand-off and an exact landing on the spawn; at least 20 px of water between the hull and every rock, the lighthouse island and the dock along the whole path; the beam on the harbor bearing for the entire countdown even with the mouse elsewhere, and normal mouse aiming afterwards; a 4:00 timer, full oxygen tanks, locked boats and lighthouse, an idle emergency boat and no round events until the end; E, Esc, right-click and held steering keys ignored during the live engine loop; activation of controls, aiming, dispatch, clock and oxygen together exactly at 3 s with normal speed, handling and collision values; identical timing at 30, 60 and 144 fps, uneven frame times and a single 5 s hitch; three consecutive replays that repeat the countdown, skip the tutorial, reset the beam and keep the star bank and upgrade; tutorial navigation unchanged. `tutorial_suite.gd` gained four checks because its launch and replay sections now wait for the countdown (176 checks).

Verified on Linux with the official Godot 4.7.2 build:

| Run | Result |
| --- | --- |
| `runtime_suite.gd`, unchanged | 109/109 |
| `tutorial_suite.gd`, `--headless` | 176/176 |
| `tutorial_suite.gd`, windowed under Xvfb (real mouse click events) | 176/176 |
| `intro_suite.gd`, `--headless --fixed-fps 60` | 132/132 |
| `intro_suite.gd`, `--headless` without `--fixed-fps` (two runs) | 132/132 each |
| `intro_suite.gd`, windowed under Xvfb | 132/132 |
| `balance_route.gd` | Output identical to the baseline commit |
| Web export in headless Chromium with software WebGL | Clicked through the tutorial, Launch Rescue played the countdown over the scene, the boat reached its berth and the clock then ran (3:59 shortly after activation) |

Mutation checks: the suite fails when the beam is not pointed at the harbor, when gameplay is not stopped during preparation, when the boat starts inside the visible area, when the path crosses a rock or the island or ends off the berth, when the countdown length or speed changes, when Replay skips the countdown or reopens the tutorial, when aiming is left enabled, and when the upgrade or star bank is reset.

Not verified: a Windows desktop run, Firefox or Safari, a GPU renderer, and display sizes other than 1152 × 648.

## Simplified HUD and survivor hearts (`feature/survivor-hearts-hud`)

The top bar now keeps the title, Level 1, TIME, ABOARD, DELIVERED, LOST and STAR BANK, and the 15-survivor heart row sits between ABOARD and DELIVERED. The emergency-boat status line, MAIN SAVES, EMERGENCY SAVES and the numeric IN THE WATER readout are gone, together with their label references. The counters behind them (`main_delivered`, `emergency_delivered`, `active_count()`) and all emergency-boat logic are unchanged, and the results screen still lists both boats' deliveries. `SurvivorHeart` (`scripts/survivor_heart.gd`) draws one heart and reads its own `Survivor` every frame (`state`, `oxygen_remaining`, `oxygen_duration`, `survivor_id`); it keeps no oxygen state of its own. `Survivor` gained two constants, `WARNING_SECONDS = 55` and `CRITICAL_SECONDS = 30`, which the map label and the hearts now share. The one gameplay-text change: the "emergency boat unavailable" message no longer points at a status line that no longer exists.

Note that these thresholds are absolute seconds, as on the map. Survivors 1, 2, 4, 6 and 10 have budgets of 34, 47, 60, 26 and 39 seconds, so their hearts start in warning or critical colours at full fill, and survivor 6 is red from the first second of play. A heart pulses only while its survivor's oxygen is really draining, so nothing pulses during the tutorial, the countdown or the pause screen.

`tests/hud_suite.gd` (80 checks headless, 87 windowed) covers: the removed text and references; layout fit, overlap and gap checks at 1152 × 648; 15 hearts bound one-to-one to the existing survivors in ID order; full hearts and green at full oxygen; fill equal to oxygen_remaining / oxygen_duration from 100% to 0%; the 55 s and 30 s colour levels and smooth colour transitions; a calm pulse only for critical hearts; boarding on the main and emergency boats (secured treatment, frozen fill, scale-pulse animation, not counted as delivered); delivery through the real harbor interaction (filled, animation, stays visible); a real oxygen run-out (hollow, shake, settles dark red, stays in place); replay reset; the pause freeze; and, when windowed, sampled screen pixels for full, half-drained, aboard, delivered and lost hearts. Each section must run to its end or the suite fails. The existing runtime suite's HUD check was rewritten for the new bar and stays at 109 checks.

Verified on Linux with the official Godot 4.7.2 build:

| Run | Result |
| --- | --- |
| `runtime_suite.gd` | 109/109 |
| `tutorial_suite.gd`, headless and windowed | 176/176 and 176/176 |
| `intro_suite.gd`, headless and windowed | 132/132 and 132/132 |
| `hud_suite.gd`, `--headless --fixed-fps 60` | 80/80 |
| `hud_suite.gd`, `--headless` at the natural frame rate | 80/80 |
| `hud_suite.gd`, windowed under Xvfb (pixel checks) | 87/87 |
| `balance_route.gd` | Output identical to the baseline commit |
| Web export in headless Chromium | The hearts drained and changed colour, and a lost survivor showed the broken-heart state with the ID digits rendered |

Mutation checks: the suite fails when the fill is inverted, when boarding is shown as delivered, when every heart pulses, when the warning colour is removed, when a lost heart is deleted, when the pulse ignores pause, when transition animations are missing or survive a replay, when the heart order is reversed, when a removed label is re-added, when a lost heart keeps fill, and when the warning threshold changes.

Not verified: a Windows desktop run, Firefox or Safari, a GPU renderer, and display sizes other than 1152 × 648. `screenshots/gameplay.png` still shows the old top bar.
