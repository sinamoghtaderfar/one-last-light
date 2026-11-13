# Verification — One Last Light 0.1

Validated on 9 November 2026 with **Godot 4.7.2 Standard**, engine build
`4.7.2.stable.official.ed1daf0bf`, on Linux x86_64.

## Engine and gameplay checks

The complete project imported in the Godot editor with **exit code 0 and no
script, scene, resource, or import errors**. The supplied runtime suite completed
with **57/57 checks passing, exit code 0, and no runtime errors**. Its recorded
output is in `tests/runtime_suite.log`.

| Requirement | Verified result |
| --- | --- |
| Configured main scene and resource paths | Main scene loads; referenced source resources exist |
| Player movement | Actual CharacterBody2D motion using input actions; acceleration and deceleration |
| Collision obstacles | Sustained movement blocked by a real rock; island collider detected by physics |
| Ten distinct survivors | Ten authored instances with different oxygen durations |
| Lighthouse | Beam rotates, checks cone angle/range, discovers contacts, preserves discovery markers |
| Oxygen | Decreases in water, stops aboard, signals loss at zero, prevents later rescue |
| Interaction and capacity | Pickups require discovery and proximity; three seats enforced; fourth seat works after upgrade |
| Harbor and scoring | Delivery empties the manifest, marks transported survivors, awards stars; empty unload gives no duplicate rewards |
| Upgrade economy | Correct prices and deductions, unaffordable/active-round purchases blocked, capacity and speed effects applied |
| Round lifecycle | Two complete rounds, results accounting, next round, restart, persistent bank/upgrades |
| Final passengers | Round stays active until the last aboard survivors reach harbor |
| Briefing and pause | Oxygen waits for launch; paused oxygen, lighthouse, and boat movement remain frozen |

The suite drives actual nodes, signals, and physics. It also teleports boats and
contacts and advances selected timers to isolate transitions; it does not measure
a human player's navigation skill or establish final game balance. The E action
routes to the same `try_interact()` method exercised by the suite.

## Rendered screen review

The Compatibility renderer also ran in a graphical Linux session using Mesa
llvmpipe / OpenGL 4.5 at the native **1152 × 648** viewport. The following actual
engine screenshots were inspected for clipping, map readability, oxygen markers,
context prompts, button states, and layout:

- `screenshots/briefing.png`
- `screenshots/gameplay.png` — normal lighthouse sweep; all ten contacts discovered
- `screenshots/pause.png`
- `screenshots/debrief.png` — scripted fixture with 3 delivered, 7 lost, 9 stars
- `screenshots/upgrade.png` — actual capacity purchase: 4 seats, 3 stars remaining

The debrief fixture resolves timers immediately, so its elapsed time reads
00:00. This is a test setup, not a measured playthrough. The virtual graphics
driver reported that changing V-Sync was unsupported; rendering and captures
completed successfully.

## Packaging and reproduction

The delivery archive is integrity-checked, contains `OneLastLight/project.godot`,
and excludes engine caches, exported builds, and unrelated workspace files. The
packaged project was extracted into a new directory, imported again, and passed
the same **57/57 runtime checks**. Import generates its own local `.godot` cache.

From the extracted `OneLastLight` directory, run:

```sh
godot --headless --path . --editor --quit
godot --headless --path . --script res://tests/runtime_suite.gd
```

To rebuild the source ZIP with Python 3 (only the packaging tool needs Python):

```sh
python3 tools/package_project.py
```

## Remaining manual validation

**A Windows executable was not exported or run in this Linux environment.** The
included Windows Desktop preset targets x86_64; matching Godot 4.7.2 Standard
export templates are required to produce the executable. Test native Windows
input, resizing, graphics-driver behavior, and export on the target machine.

A full human playtest remains useful for keyboard feel, route difficulty, oxygen
tuning, and accessibility. Current values are intentionally provisional. Fog and
storm areas are visual placeholders, and there is no saved progression between
application launches.
