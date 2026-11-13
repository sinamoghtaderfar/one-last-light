class_name Survivor
extends Node2D
## Oxygen runs only in ACTIVE. Aboard passengers are safe, but are not delivered yet.

signal discovered_now(survivor: Survivor)
signal picked_up(survivor: Survivor)
signal transported(survivor: Survivor)
signal lost(survivor: Survivor)

enum State { ACTIVE, RESCUED, TRANSPORTED, LOST }

@export var oxygen_duration: float = 120.0
@export var survivor_id: int = 1

var oxygen_remaining: float = 120.0
var discovered: bool = false
var state: State = State.ACTIVE
var _pulse_time: float = 0.0


func _ready() -> void:
	reset_survivor()


func _process(delta: float) -> void:
	_pulse_time = maxf(_pulse_time - delta, 0.0)
	if state == State.ACTIVE:
		oxygen_remaining = maxf(oxygen_remaining - delta, 0.0)
		if oxygen_remaining <= 0.0:
			state = State.LOST
			lost.emit(self)
	queue_redraw()


func discover() -> void:
	if discovered or state != State.ACTIVE:
		return
	discovered = true
	_pulse_time = 1.0
	discovered_now.emit(self)
	queue_redraw()


func pick_up() -> bool:
	if state != State.ACTIVE or not discovered or oxygen_remaining <= 0.0:
		return false
	state = State.RESCUED
	visible = false
	picked_up.emit(self)
	return true


func deliver() -> void:
	if state != State.RESCUED:
		return
	state = State.TRANSPORTED
	visible = false
	transported.emit(self)


func reset_survivor() -> void:
	state = State.ACTIVE
	oxygen_remaining = maxf(oxygen_duration, 0.01)
	discovered = false
	_pulse_time = 0.0
	visible = true
	queue_redraw()


func _draw() -> void:
	if state == State.RESCUED or state == State.TRANSPORTED:
		return
	if state == State.LOST:
		if discovered:
			draw_line(Vector2(-4, -4), Vector2(4, 4), Color("657681"), 1.5, true)
			draw_line(Vector2(-4, 4), Vector2(4, -4), Color("657681"), 1.5, true)
		return
	if not discovered:
		draw_circle(Vector2.ZERO, 3.5, Color("203d4d"))
		draw_arc(Vector2.ZERO, 7, 0.0, TAU, 20, Color("284756"), 1.0, true)
		return
	var indicator_color := Color("86dfc1")
	if oxygen_remaining <= 30.0:
		indicator_color = Color("fa877a")
	elif oxygen_remaining <= 55.0:
		indicator_color = Color("ffce7f")
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
