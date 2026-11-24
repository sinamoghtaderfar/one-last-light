# One Last Light — Graybox v0.2

A playable 2D rescue strategy game for Game Production and Management, WS 2026/27, in five levels. You steer one boat while aiming the central lighthouse with the mouse. Find the survivors, carry them to the harbor before their oxygen runs out, earn up to three stars per level, and spend the Light Points they pay in the shop.

## Open and play

1. Open this checkout on `feature/five-level-progression`, or extract the editable source archive.
2. In Godot **4.7.2 Standard**, import `project.godot` and press **F5**.
3. The game opens on the **level map**. Choose Level 1, read the three-line mission briefing (shown the first time only), then select **Launch Rescue**. Nothing moves until you do.
4. A 3 → 2 → 1 countdown plays over the live scene while the red-and-white lifeboat sails in from above the chart to the harbor on the right and the lighthouse beam points at the harbor. Controls and oxygen switch on together when the countdown ends. Every level, replay and campaign restart begins with the same countdown. In Levels 1 to 3 the countdown plays with the lighthouse only, and the boat sails in 5 seconds after the player first moves the mouse (see below).

The project uses GDScript, the Compatibility renderer and Godot's drawing primitives. The base viewport is 1152 × 648. All game content runs locally.

![Level 5 in progress (screenshot taken before the lives and tour changes)](screenshots/gameplay.png)

## Controls

| Input | Action |
| --- | --- |
| WASD or arrow keys | Steer the boat. Release the keys to decelerate. |
| Mouse | Aim the lighthouse while steering. |
| E within 48 px of a live survivor | Pick up the closest person. This works even before discovery. |
| E in the harbor | Unload everyone aboard. |
| Esc | Pause or resume oxygen, visibility memory, boat and lighthouse. |
| Left-click | Use the launch, shop, continue and retry buttons, and the Oxygen Boost button during a level. |

## The five levels

Each level has its own survivors, positions and individual oxygen budgets, defined in a `LevelDefinition` resource (`resources/levels/level_1.tres` to `level_5.tres`). Only that level's survivors are created, and a level succeeds only when every one of them is **delivered to the harbor**. A survivor who is aboard is not yet delivered.

| Level | Title | Survivors | Lives | After a win |
| ---: | --- | ---: | ---: | --- |
| 1 | First Light | 2 | 1 | Rating, points, **SHOP**, Continue |
| 2 | Two Signals | 3 | 1 | Rating, points, **SHOP**, Continue |
| 3 | Crossing Currents | 4 | 2 | Rating, points, **SHOP** (Extra Seat unlocks), Continue |
| 4 | Rocky Waters | 5 | 2 | Rating, points, **SHOP** (Faster Engine and Oxygen Boost unlock), Continue; if a boost is owned: "Take the Oxygen Boost into this level?" |
| 5 | Last Light | 6 | 3 | **All five levels complete** summary |

The boat starts with **one seat**, so every level can be finished without a single upgrade by carrying one survivor per trip. Upgrades only make that faster.

**Boat arrival (Levels 1 to 3).** Oxygen and the beam start at GO!, but the boat stays away. In Level 1 a "MOVE YOUR MOUSE" hint ("Aim the lighthouse beam to find the survivor.") appears above the lighthouse just after GO! and stays until the player first moves the mouse (at least 24 px); in Levels 2 and 3 there is no hint. After that first mouse move the boat waits 5 seconds in Level 1 and 3 seconds in Levels 2 and 3, then sails in from above the chart and steering switches on. In Levels 4 and 5 the boat sails in during the countdown as before. `boat_waits_for_mouse` and `boat_delay_after_mouse` in each level file control this.

**Level 1 guided tour** (`show_tour`). In Levels 1 and 2 (`show_progress_callout`), after the first mouse move, while the boat is on its way, a gold callout under the progress bar explains it ("Green: saved · Red: drowned · Fill it with green to win!"); the first-sighting warning waits until it is gone. When the boat arrives, the screen dims except a spotlight on the boat, and a panel above it shows the WASD and arrow keys ("MOVE YOUR BOAT") until the player first steers. Beside a survivor an E key bubble says "Press E to pick up the survivor"; at the harbor with someone aboard it says "Press E to drop off the survivor". The tour hides while paused and appears only in Level 1.

**First-sighting warning** (`first_sighting_message`). The first time a survivor is spotted in an attempt, a gold banner under the top bar warns for five seconds: Level 1 "Careful! If one person drowns, the game is lost.", Level 3 "… two people …", Level 5 "… three people …" (the levels where the number of lives changes).

### Level map

The game opens on the level map (main menu): one card per level with its number, title, best rating (0-3 stars), survivors and lives, and PLAY / REPLAY. A level opens once the level before it has been won (at least one star); until then its card is grey and LOCKED ("Win Level N first"). The furthest open level is marked NEXT. The header shows the total stars and Light Points. The map is reached from the results screen, the GAME LOST screen, the campaign summary and the pause menu (which leaves the running level without a result). Replaying pays only for stars not earned before, and the shop always sells for the furthest open level.

### Survivors and oxygen

**Random layouts.** Every attempt (first try, retry, replay) scatters the survivors at random (`scripts/survivor_layout.gd`). Spots: at least 40 px of open water to every rock and the island; **90 px inside the chart's left, right and bottom edges** and below the top strip where the warning banner appears; at least **170 px between any two survivors**; **260 to 820 px from the harbor** (nobody at the coast, nobody absurdly far); 120 px from the lighthouse; not under the Level 1 mouse hint. Of 40 draws the most spread-out one is kept (largest smallest distance between two survivors). **Air is fitted to the layout:** the level file's budgets go smallest-to-nearest, and each is raised in 5-second steps until a beginner with the starting boat (one seat, one trip each, nearest first, routes 40% longer than a straight line, 3.5 s of hesitation per trip, counting the Levels 1–3 wait) still arrives with at least 40% of that survivor's air left, before the red zone at 25%. A far survivor therefore always has enough air for the trip. These numbers are constants at the top of the script. `randomize_layouts` on the GameManager switches all of this off (the level file's positions and budgets below are then used). The balance suite plays five random layouts per level with the starting boat, plus one per upgrade state, and requires three stars every time.

The level files' survivors (the minimum air budgets for every layout, and the fallback positions):

Positions are in open water, at least 40 px of clear water from any rock, the island or the chart edge (the balance suite enforces this and the closest is 42 px). Oxygen is in seconds and starts when the level starts. A successful pickup freezes that person's oxygen.

| Level | Survivor: position → oxygen |
| ---: | --- |
| 1 | #1 (215, 335) → 120 s · #2 (640, 200) → 150 s |
| 2 | #1 (845, 205) → 35 s · #2 (380, 495) → 60 s · #3 (520, 520) → 115 s |
| 3 | #1 (860, 425) → 35 s · #2 (680, 170) → 60 s · #3 (305, 175) → 125 s · #4 (330, 485) → 95 s |
| 4 | #1 (900, 200) → 30 s · #2 (720, 500) → 40 s · #3 (480, 240) → 65 s · #4 (150, 300) → 120 s · #5 (420, 500) → 90 s |
| 5 | #1 (850, 500) → 35 s · #2 (660, 190) → 55 s · #3 (330, 200) → 80 s · #4 (130, 400) → 170 s · #5 (420, 500) → 100 s · #6 (180, 170) → 140 s |

The budgets were derived from real route lengths and the boat's real speed, then raised by about 20% in Levels 2 to 5 so that new players have some slack (see [TESTING.md](TESTING.md)). There is no time limit: oxygen is the only pressure. (The level clock still runs internally; `time_limit_enabled` in a level file would bring back the four-minute deadline, which the test suites use as a quick way to fail a level.)

### Stars, Light Points and the shop

Every won level is rated: **1 star** for finishing, **+1** if nobody drowned, **+1** if everyone you saved was picked up before their air turned red. The two bonus stars are independent: one drowned survivor with everyone else picked up in time still gives 2 stars. Each survivor's label shows the air left as minutes:seconds ("AIR 1:52"); it is green, turns yellow at half of that survivor's own air and red, with a pulsing ring, at a quarter. The thresholds are relative to each survivor's budget, so a 30-second survivor does not start out red. The balance suite checks that careful play (its bot) earns all three stars in every level without upgrades. Stars are paid out as **Light Points** (the lighthouse icon in the top bar): 1 star = 50, 2 stars = 100, 3 stars = 200. Only new stars pay: replaying a level for the same rating gives nothing, improving 2 → 3 stars gives the difference (100). A lost level pays nothing. A perfect campaign earns 1000 points.

After every won level the results screen shows the stars, the points and a **SHOP** button. The shop always shows every item. An item is grey while it is locked ("Unlocks at Level N"), needs its first phase, or costs more than the balance ("Need X more points"); it turns colourful and buyable as soon as all three are fine, and shows OWNED once bought. Buying refreshes every card, so items that became too expensive go grey again. Nothing can be bought during a level or after a lost one. "Unlocks at Level N" means buyable at the end of Level N − 1.

| Item | Effect | Price | Unlocks at |
| --- | --- | ---: | ---: |
| Extra Seat | 2 seats | 300 | Level 4 |
| Faster Engine | speed +18% | 300 | Level 5 |
| Oxygen Boost | once: +15 s for everyone in the water | 400 | Level 5 |
| Brighter Lighthouse | beam +110 px long, +0.10 rad wide | 200 | Level 6 |
| Rescue Dinghy | (placeholder: click a survivor, it fetches them) | 600 | Level 7 |
| Turbo Engine (needs Faster Engine) | speed +18% more | 400 | Level 8 |
| Third Seat (needs Extra Seat) | 3 seats | 500 | Level 9 |
| Lighthouse Lens (needs Brighter Lighthouse) | beam longer and wider again | 300 | Level 10 |

Items unlocking after Level 5 are visible but locked in this five-level campaign; the Rescue Dinghy has no behaviour yet. Items, prices and unlock levels live in `scripts/shop_catalog.gd`; the stars-to-points table is `points_for_stars` in `scripts/rescue_economy.gd`.

**New upgrade moments.** The first time the boat is ready after a purchase (after the countdown, or after the late arrival in Levels 1 to 3), the game pauses briefly for each new upgrade: a seat shows "GREAT! YOU ADDED A SEAT" while the new seat dot glows in the top bar; an engine shows "ENGINE UPGRADED!" while the camera glides in on the boat and its stern puffs exhaust (the exhaust then shows whenever the upgraded boat moves). Each moment is shown once.

**Oxygen Boost.** If the player owns an unused boost, the game asks before the next level "Take the Oxygen Boost into this level?" (YES, BRING IT / NO, SAVE IT). With YES a "+15 s" button sits at the lower left of the sea. Every time a survivor's heart turns red it shakes and says "Someone is running out of air! Click to give everyone +15 s", until it is clicked. A click adds 15 seconds to every survivor still in the water and uses the boost up.

### Ending a level

- **Victory** when every survivor still alive is delivered (with no lives left to spare that means everyone in Levels 1 and 2).
- **Losing a life.** Each survivor whose oxygen runs out costs one heart. The heart leaves the top bar and a big heart rises into the middle of the dimmed screen, cracks and falls apart ("Survivor 02 drowned · 1 life left"). If a life is left (from Level 3 on) the game is frozen for that moment and then simply continues.
- **GAME LOST · Level N** when the last life goes: one drowned survivor in Levels 1 and 2, two in Levels 3 and 4, three in Level 5. The screen appears right after the heart-break.

**RETRY LEVEL N** restores positions, oxygen, visibility, the boat and the lives, keeps the points and every upgrade you own, and plays the countdown again.

## The top bar

Icons instead of captions, left to right: the **lifeboat with one dot per seat** (large dots; a seat turns green with a person in it and a little pop when someone boards; a new seat glows the first time), the **hearts** (one per life: 1 in Levels 1 and 2, 2 in Levels 3 and 4, 3 in Level 5; a drowned survivor removes the rightmost), the **progress bar** (green from the left for delivered, pale green for aboard, red from the right for drowned, grey for still in the water, a gold tick where enough survivors are delivered to win, and "n/N" beside it), and the **Light Points** balance. Top right: "LEVEL n". There is no clock.

On the boat itself, every seat is drawn on deck (dark ring when empty, an orange life jacket when taken) and a green badge above the boat shows one person per survivor aboard. When every seat is taken (after the first pickup with one seat, after the second with two, and so on) the harbor blinks gold, ripples and shows "BRING THEM HERE" until the boat is back inside it; pressing E at a survivor with a full boat pops a "Boat full! Unload at the harbor first." bubble and nobody boards. Picking someone up pops a "Got you!" bubble over the boat; unloading pops "Bye! You're safe." (or "Bye, everyone! You're safe.").

## Design history

| System | v0.1 | v0.2 (this branch) |
| --- | --- | --- |
| Search | Automatic rotating beam and permanent markers | Mouse aim, temporary visual memory and local detection |
| Levels | One map, round counter | Five authored, data-driven levels with 1, 2, 4, 5 and 6 survivors |
| Boats | Three-seat player boat | One boat that starts with one seat and is upgraded between levels |
| Pickup | Required discovery | An in-range living survivor can board in darkness |
| Economy | Capacity and speed shop after each round | 1-3 star rating per level, paid once as Light Points, spent in an always-visible shop |

The earlier two-boat design (an autonomous emergency boat dispatched by right-click) has been removed completely: no scene, script, HUD readout, tutorial text, input or test remains.

The original project remains available at `graybox-v0.1`.

## Project structure and tuning

The editable level is `scenes/main.tscn`. It instances the boat, lighthouse, harbor and rock scenes and has an empty `World/Survivors` node into which the manager spawns each level's survivors. `scripts/main.gd` builds the HUD and screens and forwards input. `game_manager.gd` loads levels, applies the win and fail rules and owns the campaign flow, `level_clock.gd` tracks the deadline and `rescue_economy.gd` holds ratings, points and owned items, `shop_catalog.gd` lists the shop. `level_definition.gd` and `survivor_spec.gd` are the Resource types behind the level files. The top bar widgets are `seat_display.gd`, `rescue_progress.gd`, and `points_badge.gd`; `floating_text.gd` draws the "Got you!" and "Bye!" bubbles; `star_row.gd`, `shop_icon.gd`, `boost_button.gd` and `hud_icons.gd` draw the rating, the shop pictograms and the boost button. `mouse_cue.gd` draws the Level 1 mouse hint, `tour_overlay.gd` the Level 1 movement hint and E prompts, `life_heart.gd` a HUD heart and `heart_break.gd` the big heart-break. The four survivor states are `ACTIVE`, `ON_BOAT`, `DELIVERED` and `LOST`.

| Designer control | Default | Edit location |
| --- | --- | --- |
| Survivors: id, position, oxygen | See the table above | `survivors` in each `resources/levels/level_N.tres` |
| Time limit, losses allowed (lives − 1), mouse cue | off, 0 in Levels 1–2, 1 in Levels 3–4, 2 in Level 5, Level 1 only | The same level file |
| Boat waits for the mouse, its delay, guided tour, first-sighting warning | Levels 1–3, 5 s, Level 1 only, Levels 1 and 3 | The same level file |
| Shop items: price, unlock level, first phase | See "Stars, Light Points and the shop" | `scripts/shop_catalog.gd` |
| Points per rating, starting capacity | 0 / 50 / 100 / 200, 1 | Exported fields in `scripts/rescue_economy.gd` |
| Boat handling | 100 px/s, acceleration 300 and deceleration 240 px/s² | `scripts/player_boat.gd` |
| Pickup and proximity radius | 48 px, 64 px | `scripts/player_boat.gd` |
| Speed improvement | 18% of base per rank | `speed_bonus_per_level` in `scripts/player_boat.gd` |
| Lighthouse turning rate, range and full cone width | 6 rad/s, 660 px, 0.48 rad | `scripts/lighthouse.gd` |
| Visibility memory | 3 s | `visibility_memory_duration` in `scripts/survivor.gd` |
| Harbor delivery radius | 62 px | `scripts/harbor.gd` |
| Mouse cue duration and start delay | 3 s (held until the first mouse move when the boat waits), 0.8 s after activation | `scripts/mouse_cue.gd`, set in `scripts/main.gd` |

After changing a level's survivors or oxygen, run `godot --headless --path . --fixed-fps 60 --script res://tests/balance_suite.gd`. It re-validates positions and plays every level with the real boat. `tests/tools/plan_report.gd` prints clearances, route lengths and suggested oxygen budgets while authoring a level.

Rocks and the island block the hull. Rocks do not occlude the beam. There is no disk save: points, ratings and upgrades live for the current application session.

## Windows and editable source

Play directly in Godot on Windows. To build a standalone executable, install the matching 4.7.2 Standard export templates and use the included **Windows Desktop** x86_64 preset. To create an editable source ZIP, run `python tools/package_project.py` from the checkout. The tool writes `OneLastLight_Graybox_v0.2.zip` and its SHA-256 file beside the checkout. See [TESTING.md](TESTING.md) for the verification environment and commands.
