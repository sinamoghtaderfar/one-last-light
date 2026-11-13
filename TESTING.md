# Verification — One Last Light v0.2

Tested on Windows on 13 November 2026 with Godot 4.7.2 Standard, `4.7.2.stable.official.ed1daf0bf`. The v0.1 tag at `e4a78ab` passed its original **57/57** checks when independently extracted and executed on this machine.

## Reproduce

From the project directory, replace `godot` with your Godot 4.7.2 console executable if needed. On Windows, prefix a quoted executable path with the PowerShell invocation operator `&`.

```sh
godot --headless --path . --editor --import
godot --headless --path . --quit-after 30
godot --headless --path . --fixed-fps 60 --script res://tests/runtime_suite.gd
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
