class_name RescueBoat
extends CharacterBody2D
## The boat owns movement and its manifest. Currency and round results live in GameManager.

signal passenger_count_changed

@export_category("Handling")
@export var base_speed: float = 185.0
@export var acceleration: float = 530.0
@export var deceleration: float = 430.0
@export var pickup_radius: float = 48.0
@export var turn_speed: float = 10.0
@export_category("Upgrades")
@export var initial_capacity: int = 3
@export var speed_bonus_per_level: float = 0.18

var capacity: int = 3
var passengers: Array[Survivor] = []
var speed_multiplier: float = 1.0
var controls_enabled: bool = true
var heading: float = PI


func _ready() -> void:
	capacity = initial_capacity
	queue_redraw()


func _physics_process(delta: float) -> void:
	if not controls_enabled:
		velocity = Vector2.ZERO
		queue_redraw()
		return
	var movement := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var desired_velocity := movement * base_speed * speed_multiplier
	var rate := acceleration if movement.length_squared() > 0.0 else deceleration
	velocity = velocity.move_toward(desired_velocity, rate * delta)
	move_and_slide()
	if velocity.length_squared() > 16.0:
		heading = lerp_angle(heading, velocity.angle(), minf(turn_speed * delta, 1.0))
	queue_redraw()


func apply_upgrades(capacity_level: int, speed_level: int) -> void:
	capacity = initial_capacity + maxi(capacity_level, 0)
	speed_multiplier = 1.0 + maxi(speed_level, 0) * speed_bonus_per_level
	passenger_count_changed.emit()
	queue_redraw()


func try_board(survivor: Survivor) -> bool:
	if not is_instance_valid(survivor) or is_full():
		return false
	if survivor.state != Survivor.State.ACTIVE or not survivor.discovered:
		return false
	if global_position.distance_to(survivor.global_position) > pickup_radius:
		return false
	if not survivor.pick_up():
		return false
	passengers.append(survivor)
	passenger_count_changed.emit()
	queue_redraw()
	return true


func unload_passengers() -> Array[Survivor]:
	var delivered: Array[Survivor] = passengers.duplicate()
	# Clear the manifest before signals fire so every observer sees the same state.
	passengers.clear()
	for survivor in delivered:
		if is_instance_valid(survivor):
			survivor.deliver()
	passenger_count_changed.emit()
	queue_redraw()
	return delivered


func reset_boat(spawn_position: Vector2) -> void:
	global_position = spawn_position
	velocity = Vector2.ZERO
	heading = PI
	passengers.clear()
	controls_enabled = true
	passenger_count_changed.emit()
	queue_redraw()


func is_full() -> bool:
	return passengers.size() >= capacity


func _draw() -> void:
	var accent := Color("ffca79") if is_full() else Color("7fe0d8")
	# This faint ring exposes the actual interaction range during route planning.
	draw_arc(Vector2.ZERO, pickup_radius, 0.0, TAU, 48, Color(accent, 0.13), 1.0, true)
	draw_set_transform(Vector2.ZERO, heading)
	if velocity.length_squared() > 100.0:
		var wake_length := clampf(velocity.length() * 0.11, 3.0, 26.0)
		draw_line(Vector2(-16, -5), Vector2(-18 - wake_length, -10), Color(0.65, 0.88, 0.91, 0.32), 1.5, true)
		draw_line(Vector2(-16, 5), Vector2(-18 - wake_length, 10), Color(0.65, 0.88, 0.91, 0.32), 1.5, true)
	var hull := PackedVector2Array([Vector2(20, 0), Vector2(9, -11), Vector2(-15, -10), Vector2(-18, -6), Vector2(-18, 6), Vector2(-15, 10), Vector2(9, 11)])
	draw_colored_polygon(hull, Color("d9e9e7"))
	var outline := hull.duplicate()
	outline.append(hull[0])
	draw_polyline(outline, Color("365960"), 1.5, true)
	draw_rect(Rect2(-8, -7, 15, 14), Color("25434d"))
	draw_rect(Rect2(1, -5, 5, 10), Color("7fe0d8"))
	draw_line(Vector2(-13, -8), Vector2(-13, 8), Color("e9aa68"), 3.0, true)
	draw_circle(Vector2(13, 0), 2.3, accent)
	# Passenger pips make a loaded boat recognizable without reading the HUD.
	for index in range(passengers.size()):
		var row := floori(index / 4.0)
		var column := index % 4
		draw_circle(Vector2(-8 + column * 3, -3 + row * 5), 1.25, Color("ffda9b"))
	draw_set_transform(Vector2.ZERO)
