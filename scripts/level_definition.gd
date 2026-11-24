class_name LevelDefinition
extends Resource
## Everything one level needs. The game manager builds the level from this and nothing else.

@export_range(1, 99) var level_number: int = 1
@export var title: String = ""
@export var survivors: Array[SurvivorSpec] = []
@export_range(10.0, 900.0) var time_limit: float = 240.0
## Off by default: the clock is hidden and never ends a level; oxygen is the only pressure.
@export var time_limit_enabled: bool = false
## Survivors that may be lost while the level is still a success. Zero: everyone must be delivered.
## The HUD shows allowed_losses + 1 lives; losing the last one fails the level.
@export_range(0, 98) var allowed_losses: int = 0
@export var show_mouse_cue: bool = false
## When true, the level starts with the lighthouse only: the rescue boat stays away until the
## player first moves the mouse, then sails in after boat_delay_after_mouse seconds.
@export var boat_waits_for_mouse: bool = false
@export_range(0.0, 30.0) var boat_delay_after_mouse: float = 5.0
## Guided tour (Level 1): movement hint when the boat arrives, and E prompts for pickup and drop-off.
@export var show_tour: bool = false
## Explain the progress bar (callout under the top bar) while the boat is on its way.
@export var show_progress_callout: bool = false
## Shown once per attempt, the first time a survivor is spotted. Empty: no message.
@export_multiline var first_sighting_message: String = ""


func survivor_count() -> int:
	return survivors.size()


## Every delivery the level needs for success.
func lives() -> int:
	return allowed_losses + 1


func required_deliveries() -> int:
	return survivors.size() - allowed_losses

