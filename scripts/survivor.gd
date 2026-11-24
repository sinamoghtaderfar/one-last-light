class_name Survivor
extends Node2D
## Oxygen runs only in ACTIVE. Aboard passengers are safe, but are not delivered yet.

signal discovered_now(survivor: Survivor)
signal picked_up(survivor: Survivor)
signal transported(survivor: Survivor)
signal lost(survivor: Survivor)
## Oxygen dropped to the critical level (the red heart) while still in the water.
signal turned_critical(survivor: Survivor)

enum State { ACTIVE, ON_BOAT, DELIVERED, LOST }

@export var oxygen_duration: float = 120.0
## The authored budget; oxygen_duration can grow during a level through the Oxygen Boost.
var base_oxygen: float = -1.0
@export var survivor_id: int = 1
@export var visibility_memory_duration: float = 3.0

## Oxygen warning levels as a share of the survivor's own air: yellow at half, red at a quarter.
## Relative, so a 30-second survivor does not start out red and a 140-second one is not red for long.
const WARNING_RATIO := 0.5
const CRITICAL_RATIO := 0.25

var oxygen_remaining: float = 120.0
var discovered: bool = false
var state: State = State.ACTIVE
var _pulse_time: float = 0.0
var _memory_remaining: float = 0.0


func _ready() -> void:
	reset_survivor()


func _process(delta: float) -> void:
	if state != State.ACTIVE:
		return
	_pulse_time = maxf(_pulse_time - delta, 0.0)
	var was_critical := is_critical()
	oxygen_remaining = maxf(oxygen_remaining - delta, 0.0)
	if not was_critical and is_critical() and oxygen_remaining > 0.0:
		turned_critical.emit(self)
	if is_critical():
		queue_redraw()
	if oxygen_remaining <= 0.0:
		state = State.LOST
		_hide_contact()
		lost.emit(self)
	elif visible:
		queue_redraw()


func update_visibility(detected: bool, delta: float) -> void:
	if state != State.ACTIVE:
		return
	if detected:
		discover()
	elif discovered:
		_memory_remaining = maxf(_memory_remaining - delta, 0.0)
		if _memory_remaining <= 0.0:
			_hide_contact()


func discover() -> void:
	if state != State.ACTIVE:
		return
	_memory_remaining = visibility_memory_duration
	if discovered:
		return
	discovered = true
	visible = true
	_pulse_time = 1.0
	discovered_now.emit(self)
	queue_redraw()


func pick_up() -> bool:
	if state != State.ACTIVE or oxygen_remaining <= 0.0:
		return false
	state = State.ON_BOAT
	_hide_contact()
	picked_up.emit(self)
	return true


func deliver() -> void:
	if state != State.ON_BOAT:
		return
	state = State.DELIVERED
	transported.emit(self)


## A new spot and air budget for this attempt (the random layout). Call before reset_survivor().
func configure(spot: Vector2, budget: float) -> void:
	position = spot
	oxygen_duration = budget
	base_oxygen = budget


func critical_seconds() -> float:
	return (base_oxygen if base_oxygen > 0.0 else oxygen_duration) * CRITICAL_RATIO


func warning_seconds() -> float:
	return (base_oxygen if base_oxygen > 0.0 else oxygen_duration) * WARNING_RATIO


func is_critical() -> bool:
	return oxygen_remaining <= critical_seconds()


## Remaining air as the player reads it: "1:52", "0:07".
func air_text() -> String:
	var seconds := ceili(oxygen_remaining)
	return "%d:%02d" % [floori(seconds / 60.0), seconds % 60]


## Oxygen Boost: extra seconds for someone still in the water.
func add_oxygen(seconds: float) -> void:
	if state != State.ACTIVE:
		return
	oxygen_remaining += seconds
	oxygen_duration = maxf(oxygen_duration, oxygen_remaining)
	_pulse_time = 1.0
	queue_redraw()


func reset_survivor() -> void:
	state = State.ACTIVE
	if base_oxygen < 0.0:
		base_oxygen = oxygen_duration
	oxygen_duration = base_oxygen
	oxygen_remaining = maxf(oxygen_duration, 0.01)
	_hide_contact()
	_pulse_time = 0.0


func _hide_contact() -> void:
	discovered = false
	visible = false
	_memory_remaining = 0.0


func _draw() -> void:
	var indicator_color := Color("87dfa3")
	var critical := is_critical()
	if critical:
		indicator_color = Color("fa877a")
	elif oxygen_remaining <= warning_seconds():
		indicator_color = Color("ffdc70")
	if _pulse_time > 0.0:
		draw_arc(Vector2.ZERO, 12.0 + (1.0 - _pulse_time) * 28.0, 0.0, TAU, 36, Color(indicator_color, _pulse_time * 0.7), 1.5, true)
	if critical:
		# Red zone: a pulsing red ring, so "this one first!" is obvious on the map.
		var beat := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.012)
		draw_arc(Vector2.ZERO, 15.0 + 3.0 * beat, 0.0, TAU, 32, Color(indicator_color, 0.5 + 0.4 * beat), 2.5, true)
	draw_circle(Vector2.ZERO, 11.0, Color(0.03, 0.10, 0.16, 0.8))
	draw_arc(Vector2.ZERO, 8.0, 0.0, TAU, 24, Color("e5ae67"), 3.0, true)
	draw_line(Vector2(-5, 0), Vector2(5, 0), Color("f5e6c9"), 2.0, true)
	draw_circle(Vector2(0, -2), 3.0, Color("f5e6c9"))
	# Air left: a bar and the time as minutes:seconds, both counting down in real seconds.
	draw_rect(Rect2(-26, 16, 52, 6), Color("253d4a"))
	var oxygen_ratio := clampf(oxygen_remaining / maxf(oxygen_duration, 0.01), 0.0, 1.0)
	draw_rect(Rect2(-26, 16, 52 * oxygen_ratio, 6), indicator_color)
	draw_string(ThemeDB.fallback_font, Vector2(-30, 38), "AIR " + air_text(), HORIZONTAL_ALIGNMENT_CENTER, 60, 13, indicator_color)
