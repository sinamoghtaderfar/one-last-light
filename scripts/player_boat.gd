class_name RescueBoat
extends CharacterBody2D
## The boat owns movement and its manifest. Currency and round results live in GameManager.

signal passenger_count_changed

@export_category("Handling")
@export var base_speed: float = 100.0
@export var acceleration: float = 300.0
@export var deceleration: float = 240.0
@export var pickup_radius: float = 48.0
@export var proximity_radius: float = 64.0
@export var turn_speed: float = 10.0
@export_category("Upgrades")
@export_range(1, 12) var initial_capacity: int = 1
@export var speed_bonus_per_level: float = 0.18

var capacity: int = 1
var passengers: Array[Survivor] = []
var speed_multiplier: float = 1.0
var controls_enabled: bool = true
var heading: float = PI
## Owned engine upgrades. From level 1 the stern shows an exhaust while the boat moves.
var speed_level: int = 0
## Set while the "engine upgraded" moment is on screen: a big exhaust even at rest.
var showcase_exhaust: bool = false
var _collision_flash: float = 0.0
var _engine_time: float = 0.0


func _ready() -> void:
	capacity = initial_capacity
	queue_redraw()


func _process(delta: float) -> void:
	_engine_time += delta
	if speed_level > 0 and (showcase_exhaust or velocity.length_squared() > 100.0):
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
	_collision_flash = maxf(0.0, _collision_flash - delta)
	if get_slide_collision_count() > 0:
		_collision_flash = 0.18
	if velocity.length_squared() > 16.0:
		heading = lerp_angle(heading, velocity.angle(), minf(turn_speed * delta, 1.0))
	queue_redraw()


## The economy owns the real values; the boat only applies them. capacity is the total seat count.
func apply_upgrades(total_capacity: int, speed_level: int) -> void:
	capacity = maxi(total_capacity, 1)
	self.speed_level = maxi(speed_level, 0)
	speed_multiplier = 1.0 + self.speed_level * speed_bonus_per_level
	passenger_count_changed.emit()
	queue_redraw()


func try_board(survivor: Survivor) -> bool:
	if not is_instance_valid(survivor) or is_full():
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
	_collision_flash = 0.0
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
	var moving := velocity.length_squared() > 100.0
	if moving:
		var wake_length := clampf(velocity.length() * 0.11, 3.0, 26.0)
		draw_line(Vector2(-16, -5), Vector2(-18 - wake_length, -10), Color(0.65, 0.88, 0.91, 0.32), 1.5, true)
		draw_line(Vector2(-16, 5), Vector2(-18 - wake_length, 10), Color(0.65, 0.88, 0.91, 0.32), 1.5, true)
	if speed_level > 0 and (moving or showcase_exhaust):
		_draw_exhaust(2.0 if showcase_exhaust else 1.0)
	# Lifeboat colours: white hull, red band and red bow.
	var hull := PackedVector2Array([Vector2(20, 0), Vector2(9, -11), Vector2(-15, -10), Vector2(-18, -6), Vector2(-18, 6), Vector2(-15, 10), Vector2(9, 11)])
	draw_colored_polygon(hull, Color("f6f3ec"))
	draw_colored_polygon(PackedVector2Array([Vector2(20, 0), Vector2(9, -11), Vector2(5, -10.5), Vector2(12, 0), Vector2(5, 10.5), Vector2(9, 11)]), Color("d9363e"))
	draw_line(Vector2(-15, -8.2), Vector2(6, -9.2), Color("d9363e"), 2.6, true)
	draw_line(Vector2(-15, 8.2), Vector2(6, 9.2), Color("d9363e"), 2.6, true)
	var outline := hull.duplicate()
	outline.append(hull[0])
	var outline_color := Color("fa877a") if _collision_flash > 0.0 else Color("5a2a2e")
	draw_polyline(outline, outline_color, 2.0, true)
	draw_rect(Rect2(-8, -6, 14, 12), Color("c9d6d8"))
	draw_rect(Rect2(-8, -6, 14, 12), Color("5a2a2e"), false, 1.0)
	draw_rect(Rect2(1, -4, 4, 8), Color("7fe0d8"))
	draw_line(Vector2(-16, -7), Vector2(-16, 7), Color("d9363e"), 3.0, true)
	draw_circle(Vector2(14, 0), 2.0, accent)
	# Seats on deck: an empty seat is a dark ring, a rescued survivor is an orange life jacket with a
	# head, so a loaded boat is obvious at a glance.
	var seats := [Vector2(-12, -4.5), Vector2(-12, 4.5), Vector2(11, 0)]
	for index in range(mini(capacity, seats.size())):
		var spot: Vector2 = seats[index]
		if index < passengers.size():
			draw_circle(spot, 4.2, Color("ff8a2a"))
			draw_circle(spot, 2.6, Color("f5d7b0"))
			draw_arc(spot, 4.2, 0.0, TAU, 16, Color("5a2a2e"), 1.0, true)
		else:
			draw_arc(spot, 3.4, 0.0, TAU, 16, Color(0.2, 0.3, 0.35, 0.9), 1.4, true)
	draw_set_transform(Vector2.ZERO)
	# Passenger badge above the boat (never rotated): one green person per survivor aboard.
	if not passengers.is_empty():
		var count := passengers.size()
		var width := 10.0 + count * 14.0
		var badge := StyleBoxFlat.new()
		badge.bg_color = Color("1f6b45")
		badge.border_color = Color("6fe39a")
		badge.set_border_width_all(2)
		badge.set_corner_radius_all(9)
		draw_style_box(badge, Rect2(Vector2(-width * 0.5, -36), Vector2(width, 18)))
		for index in range(count):
			var center := Vector2(-width * 0.5 + 12.0 + index * 14.0, -27)
			draw_circle(center + Vector2(0, -2.5), 3.0, Color.WHITE)
			draw_colored_polygon(PackedVector2Array([center + Vector2(-5, 6), center + Vector2(-4, 1.5), center + Vector2(4, 1.5), center + Vector2(5, 6)]), Color.WHITE)


## Puffs of engine exhaust drifting back from the stern; bigger during the upgrade showcase.
func _draw_exhaust(strength: float) -> void:
	var puffs := 5 + speed_level * 2
	for index in range(puffs):
		var phase := fposmod(_engine_time * (1.6 + 0.4 * speed_level) + index / float(puffs), 1.0)
		var side := -1.0 if index % 2 == 0 else 1.0
		var point := Vector2(-20.0 - phase * 26.0 * strength, side * (3.0 + phase * 5.0))
		var radius := (2.0 + phase * 4.5) * (0.7 + 0.3 * strength)
		var color := Color("ffb35c").lerp(Color("b8c4c8"), phase)
		draw_circle(point, radius, Color(color, (1.0 - phase) * 0.75))
	draw_circle(Vector2(-19, 0), 2.6 * strength, Color("ffcf6b", 0.9))
