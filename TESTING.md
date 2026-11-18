# Verification — One Last Light v0.2, five-level campaign

Branch `feature/five-level-progression`. Everything below was run on Linux with the official Godot 4.7.2 Standard build (`4.7.2.stable.official.ed1daf0bf`), headless, windowed under Xvfb (Mesa llvmpipe, OpenGL 3.3 Compatibility) and as a single-threaded Web export in headless Chromium. It was **not** run on a Windows desktop, with a GPU renderer, in Firefox or Safari, or at display sizes other than 1152 × 648.

## Reproduce

From the project directory, replace `godot` with your Godot 4.7.2 console executable if needed. On Windows, prefix a quoted executable path with the PowerShell invocation operator `&`.

```sh
godot --headless --path . --editor --import
godot --headless --path . --quit-after 30
godot --headless --path . --fixed-fps 60 --script res://tests/runtime_suite.gd
godot --headless --path . --fixed-fps 60 --script res://tests/tutorial_suite.gd
godot --headless --path . --fixed-fps 60 --script res://tests/intro_suite.gd
godot --headless --path . --fixed-fps 60 --script res://tests/hud_suite.gd
godot --headless --path . --fixed-fps 60 --script res://tests/progression_suite.gd
godot --headless --path . --fixed-fps 60 --script res://tests/balance_suite.gd
```

Each suite prints `NAME SUITE: n/n checks passed` and exits non-zero on any failure. The tutorial, intro and HUD suites need a window for their real mouse clicks and pixel checks; under Xvfb, prefix them with `xvfb-run -a -s "-screen 0 1280x800x24"` and add `--rendering-driver opengl3` instead of `--headless`. In `--headless` mode the display server drops mouse events, so those suites press buttons by emitting their `pressed` signal, and the log header (`Display: headless` or `Display: X11`) says which mode ran. `tests/tools/plan_report.gd` is an authoring aid, not a test.

## Results

| Run | Result |
| --- | --- |
| `--editor --quit` import and `--quit-after 30` startup, with the emergency-boat files deleted | Exit 0, no errors |
| `runtime_suite.gd`, headless | 76/76 |
| `tutorial_suite.gd`, headless | 185/185 |
| `tutorial_suite.gd`, windowed (real mouse click events) | 185/185 |
| `intro_suite.gd`, headless | 130/130 |
| `intro_suite.gd`, windowed | 130/130 |
| `hud_suite.gd`, headless | 160/160 |
| `hud_suite.gd`, windowed (adds the sampled-pixel section) | 167/167 |
| `progression_suite.gd`, headless | 632/632 |
| `progression_suite.gd`, windowed | 632/632 |
| `runtime_suite.gd`, windowed | 76/76 |
| `balance_suite.gd`, headless | 179/179 |

The windowed runs print one `ERR_CANT_OPEN` line from the audio driver (no sound card in the sandbox). Godot falls back to a dummy driver; the baseline logs show the same line.

The five suites that existed before this work were ported to the one-boat, five-level game, not deleted. Their check counts changed because checks that only made sense with the emergency boat were removed and the rest were reworded for the new rules:

| Suite | Baseline | Now | What changed |
| --- | ---: | ---: | --- |
| runtime | 109 | 76 | Rewritten around Level 1 as shipped plus a Level 3 capacity fixture. Dropped: emergency navigation, availability, dispatch and emergency-victory checks (about 31), and the old rules they sat beside (15 survivors, two seats, three-loss threshold, results-screen speed shop prices). Their replacements are in the progression and balance suites. |
| tutorial | 176 | 185 | New page text, dynamic-content checks, no right-click dispatch, and a Level 1 win → upgrade → Level 2 → timeout → replay flow. |
| intro | 132 | 130 | Emergency references removed. The replay section now wins Level 1, fixes up capacity and speed, fails Level 2 and replays it three times. |
| hud | 80 / 87 windowed | 160 / 167 | 15 fixed hearts replaced by dynamic hearts for all five levels, restart, replay and advance, plus equal-gap layout checks. |
| balance_route | 3 scenarios | replaced by `balance_suite` | The emergency-boat reference routes no longer exist. |

## Progression suite (`tests/progression_suite.gd`, 632 checks)

It drives the real Main scene through its own screens. Where a step would need real piloting, the boat is placed by hand beside a survivor and E is pressed through the game manager; physics is the balance suite's job.

| Area | What it checks |
| --- | --- |
| Level data | Exactly five levels. Survivor counts 1, 2, 4, 5 and 6, with unique ids, unique positions and individual positive oxygen. Only the loaded level's survivors exist anywhere in the scene tree. The 4:00 clock, mouse cue only on Level 1, offer table (3, 6, and the exclusive 9 + 9 choice), +18% speed step. |
| Hearts and HUD | One heart per survivor, each bound to a survivor of that level, "LEVEL n / 5", 0/n delivered, starting capacity 1 and no stars. |
| Level 1 cue | Hidden before activation and during the whole intro. Starts at activation but stays invisible while GO! is on screen, then fades in, holds, fades out and disappears after about 3 s. Anchored to the lighthouse, inside the chart, covering neither lighthouse, harbor nor survivor, exact text, no controls, does not block steering or the clock, freezes with pause, does not restart in the same level, absent in Level 2, replays on a Level 1 replay and after a campaign restart. |
| Rescue and Level 1 popup | The survivor is far from the harbor. Boarding is not a win and earns nothing. Delivery wins exactly once (forced second `_end_round` calls change nothing), 3 stars, "LEVEL 1 COMPLETE", "You earned 3 stars!", "Upgrade your boat capacity from 1 to 2 passengers?", `UPGRADE — 3 STARS` and `NOT NOW`. Three presses buy once, cost exactly 3, the popup keeps saying 1 to 2 afterwards, and a double click on Continue does not skip Level 2. |
| Declining | NOT NOW buys nothing, keeps the stars and continues. Level 2 is won in two trips with capacity 1. The Level 2 offer then shows the real 1 to 2 values at 6 stars. |
| Three whole campaigns | Speed branch (L1 and L2 capacity, then speed), capacity branch (three capacity upgrades), and no upgrades with one survivor per trip. For every level: the right survivors, hearts and boat seats and speed, HUD seats and bank, cue only in Level 1, ceil(n / capacity) trips, one victory, 3 stars per survivor, bank arithmetic, Level 3 forces no upgrade, Level 4 opens "PREPARE FOR LEVEL 5" with "Six survivors are waiting. Choose your next boat upgrade.", both cards at 9 stars with real before and after values, Keep My Stars, the other upgrade locked after one is bought and refusing presses, "START LEVEL 5", no tutorial reopening. Final screen: ALL FIVE LEVELS COMPLETE, victory message, 18 rescued, 54 earned, the remaining bank, the upgrade summary, Restart Campaign, no sixth level. |
| Economy guards | One star short disables the button but still shows the real price and says how many stars are missing. A press on the disabled button, an unknown offer, or a mid-level purchase changes nothing. Capacity stops at its maximum without spending a star. |
| Failure and replay | Timeout and survivor loss each end the level exactly once. The reason is shown. Unbanked stars from an unfinished attempt vanish. Replay replays the countdown, restores survivors, hearts and clock, keeps upgrades and the bank, and does not reopen the tutorial or duplicate survivors or hearts. A lost survivor is restored. All survivors aboard is not a win. |
| Restart | Stars, capacity, speed, totals and purchase history reset, one survivor and one heart, the cue plays again, the first offer can be bought exactly once again. The final screen's own button does the same and a double click starts only one countdown. |
| Emergency boat gone | No node, script, label, button or property in the running game mentions an emergency boat. No input action does. Exactly one `RescueBoat`. A right-click on a survivor does nothing. `main.gd` and `game_manager.gd` contain no emergency or right-click code. |

The countdown is exercised at every level of every campaign: during the intro the clock stays at the level's full time, every oxygen tank stays full and the boat and beam stay off, and gameplay starts when it ends.

## Balance suite (`tests/balance_suite.gd`, 179 checks)

Level data is validated first: counts, unique ids and positions, survivors at least 100 px apart so labels never overlap, at least 40 px of clear water around each (the closest is 42 px), clear of the harbor and the lighthouse, reachable by a collision-free route, Level 1 at least 600 px from the harbor with at least 120 s of oxygen.

Then a bot plays every level with the real engine. It steers with the real input actions (eight-way held keys, as on a keyboard), follows hull-clear routes planned with `RoutePlanner` (a visibility graph on `AStar2D` that tests segments with the boat's own collision shape, kept 10 px from obstacles), aims the beam, presses E and unloads. `LevelPlanner` chooses the survivor order and trip split that maximise the smallest oxygen reserve; its time model uses a 34 px standoff, a 1.06 turn factor, 3 s per trip and 1 s per pickup. The bot's foreknowledge of the map is the limit of this method: it shows that a good route exists and how tight it is, not how long a new player needs to find the survivors.

Each run must win, finish with at least 40% of the 240 s clock left, keep at least 8 s of oxygen in reserve at every pickup, and pay 3 stars per delivery. The 15 configurations cover every state a player can reach at each level. Oxygen budgets were set from the planner's times, then retuned until the tightest no-upgrade reserve was around 18 to 24 s.

| Level | Boat | Elapsed (s) | Tightest oxygen reserve at pickup (s) | Trips |
| --- | --- | ---: | ---: | --- |
| 1 | capacity 1 | 21.6 | 107.8 | 1 |
| 2 | capacity 1 (declined L1) | 29.2 | 23.7 | 1 + 1 |
| 2 | capacity 2 | 20.0 | 24.1 | 2 together |
| 3 | capacity 1 | 62.4 | 23.4 | four single trips |
| 3 | capacity 2 | 39.2 | 24.3 | 2 + 2 |
| 3 | capacity 3 | 35.6 | 22.5 | 1 + 3 |
| 4 | capacity 1 | 82.9 | 19.2 | five single trips |
| 4 | capacity 2 | 61.7 | 17.4 | 1 + 2 + 2 |
| 4 | capacity 3 | 40.5 | 19.3 | 2 + 3 |
| 5 | capacity 1, no upgrades | 106.5 | 18.0 | six single trips |
| 5 | capacity 1, speed +18% | 99.6 | 23.6 | six single trips |
| 5 | capacity 2 | 70.9 | 23.6 | 2 + 2 + 2 |
| 5 | capacity 3 | 63.2 | 24.0 | 3 + 3 |
| 5 | capacity 3, speed +18% | 55.2 | 23.8 | 3 + 3 |
| 5 | capacity 4 | 55.7 | 24.0 | 2 + 4 |

Every level is therefore solvable with capacity 1 and no upgrades, and the 240 s deadline never decides a level for a pilot this good. The reserves say the oxygen budgets bind. A new player will lose more time searching, so playtests should decide whether any budget needs loosening.

## Mutation checks

Each row is a deliberate one-line break of the game; the suite named must fail.

| Break | Result |
| --- | --- |
| Cue lasts 6 s instead of 3 | progression fails (1 check) |
| Cue shown in every level | progression fails (14) |
| Cue starts during the intro | progression fails (17) |
| Intro starts gameplay early | progression fails (39) |
| An upgrade can be bought twice | progression fails (23) |
| An upgrade jumps two steps (1 → 3) | progression fails (55) |
| An upgrade costs nothing | progression fails (37) |
| Exclusive Level 5 offers not locked | progression fails (16) |
| Failed attempts bank their stars | progression fails (2) |
| Survivors aboard count as a win | progression fails (126) |
| Previous level's survivors not cleared | progression fails (143) |
| Restart keeps claimed offers | progression fails (2) |
| Restart screen button skips the reset | progression fails (2) |
| A sixth level is reachable | progression fails (3) |
| A finished level can be ended and paid a second time | **first survived**; a forced double `_end_round` check was added and the break now fails (2) |
| Replay does not re-apply the upgrades | progression fails (1, only through a campaign restart) |

The HUD, intro, runtime and tutorial suites kept the mutation checks recorded for the features they were first written for, and their ported assertions were not weakened.

## Rendered review

Windowed screenshots at 1152 × 648 were taken of every tutorial page, each level's start and finish, the Level 1 cue (before, fading in, full, fading out, gone), both upgrade popups before and after purchase, the Level 3 complete screen with no offer, the Prepare for Level 5 screen before and after buying speed, the pause screen, a survivor-lost failure, a timeout failure, the final screen and a restarted Level 1, with 1, 2, 4, 5 and 6 hearts on screen. They found and led to fixes for three real problems: the cue overlapped the GO! flash; a bought upgrade card showed the next step's numbers (for example "+18% to +36%"); and "1 of 1 survivors". The five captures in `screenshots/` (`briefing`, `gameplay`, `pause`, `debrief`, `upgrade`) were refreshed from this run.

The Web export was built from a copy of the project with one extra test-only autoload that wins each level five seconds after it activates (it is not part of this project). In headless Chromium with software WebGL there were no console errors beyond the engine's start-up lines. The tutorial pages, the countdown, the Level 1 cue, the one-heart HUD, the Level 1 popup with `UPGRADE — 3 STARS` and its em dash, the purchase, Level 2 and the Level 3 complete screen with four hearts all rendered. The browser run stopped at the Level 3 screen (a scripted click missed the button), so Levels 4 and 5 and the Prepare for Level 5 screen were verified in the windowed Linux run only. The bundled UI font renders the em dash, and the tutorial still draws its arrows from an inline SVG because that font has no arrow glyphs.

## Remaining human playtests

1. Give a new player the tutorial and a fresh bank. Record Level 1: how long they take to find the survivor, whether they notice the mouse cue, and whether 120 s of oxygen is generous or too long.
2. Watch the first two or three attempts at Levels 4 and 5 without upgrades. Check whether the 18 to 24 s reserves the bot achieves are reachable for a human who must search first.
3. Ask whether the choice on the Prepare for Level 5 screen is understood: speed +18% against one more seat, with only one affordable per campaign.
4. Inspect oxygen numbers, hearts and the red, yellow and green states at the target display scale, with mouse aim, WASD and E on a physical keyboard.
5. Run a Windows desktop session on the real GPU.
