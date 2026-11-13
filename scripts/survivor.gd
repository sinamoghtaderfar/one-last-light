class_name Survivor
extends Node2D
## Oxygen runs only in ACTIVE. Aboard passengers are safe, but are not delivered yet.

signal discovered_now(survivor: Survivor)
signal picked_up(survivor: Survivor)
signal transported(survivor: Survivor)
signal lost(survivor: Survivor)

enum State { ACTIVE, ON_MAIN_BOAT, ON_EMERGENCY_BOAT, DELIVERED, LOST }

@export var oxygen_duration: float = 120.0
@export var survivor_id: int = 1
@export var visibility_memory_duration: float = 3.0

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
	oxygen_remaining = maxf(oxygen_remaining - delta, 0.0)
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


func pick_up(emergency: bool = false) -> bool:
	if state != State.ACTIVE or oxygen_remaining <= 0.0:
		return false
	state = State.ON_EMERGENCY_BOAT if emergency else State.ON_MAIN_BOAT
	_hide_contact()
	picked_up.emit(self)
	return true


func deliver() -> void:
	if state != State.ON_MAIN_BOAT and state != State.ON_EMERGENCY_BOAT:
		return
	state = State.DELIVERED
	transported.emit(self)


func reset_survivor() -> void:
	state = State.ACTIVE
	oxygen_remaining = maxf(oxygen_duration, 0.01)
	_hide_contact()
	_pulse_time = 0.0


func _hide_contact() -> void:
	discovered = false
	visible = false
	_memory_remaining = 0.0


func _draw() -> void:
	var indicator_color := Color("87dfa3")
	if oxygen_remaining <= 30.0:
		indicator_color = Color("fa877a")
	elif oxygen_remaining <= 55.0:
		indicator_color = Color("ffdc70")
	if _pulse_time > 0.0:
		draw_arc(Vector2.ZERO, 12.0 + (1.0 - _pulse_time) * 28.0, 0.0, TAU, 36, Color(indicator_color, _pulse_time * 0.7), 1.5, true)
	draw_circle(Vector2.ZERO, 11.0, Color(0.03, 0.10, 0.16, 0.8))
	draw_arc(Vector2.ZERO, 8.0, 0.0, TAU, 24, Color("e5ae67"), 3.0, true)
	draw_line(Vector2(-5, 0), Vector2(5, 0), Color("f5e6c9"), 2.0, true)
	draw_circle(Vector2(0, -2), 3.0, Color("f5e6c9"))
	draw_rect(Rect2(-24, 16, 48, 4), Color("253d4a"))
	var oxygen_ratio := clampf(oxygen_remaining / maxf(oxygen_duration, 0.01), 0.0, 1.0)
	draw_rect(Rect2(-24, 16, 48 * oxygen_ratio, 4), indicator_color)
	var oxygen_text := "%02d  %ds" % [survivor_id, ceili(oxygen_remaining)]
	draw_string(ThemeDB.fallback_font, Vector2(-24, 34), oxygen_text, HORIZONTAL_ALIGNMENT_CENTER, 48, 12, indicator_color)
