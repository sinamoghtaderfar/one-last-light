class_name EmergencyBoat
extends CharacterBody2D
## An assignment remains valid after the contact's visibility memory expires.

signal delivered(count: int)

enum State { READY, TRAVELING, RESCUING, RETURNING, COOLDOWN }

const BoatRoutes := preload("res://scripts/boat_routes.gd")
const ACCENT := Color("ffaa75")

@export_range(1, 10) var capacity: int = 1
@export_range(1.0, 500.0) var speed: float = 74.0
@export_range(0.0, 120.0) var cooldown_duration: float = 24.0
@export_range(1.0, 100.0) var pickup_radius: float = 22.0
@export_range(0.0, 5.0) var rescue_duration: float = 0.65

var state: State = State.READY
var target: Survivor
var passengers: Array[Survivor] = []
var cooldown_remaining: float = 0.0

var _harbor: Harbor
var _routes: BoatRoutes
var _berth: Vector2
var _path := PackedVector2Array()
var _rescue_remaining: float = 0.0
var _replan_remaining: float = 0.0
var _heading: float = PI


func configure(dock: Harbor, world: Node2D) -> void:
	_harbor = dock
	_berth = global_position if dock.contains_point(global_position) else dock.global_position
	var hull := $CollisionShape2D.shape as CircleShape2D
	_routes = BoatRoutes.new(self, world, hull.radius)
	reset_boat()
	set_running(false)


func reset_boat() -> void:
	global_position = _berth
	velocity = Vector2.ZERO
	_heading = PI
	target = null
	passengers.clear()
	_path.clear()
	cooldown_remaining = 0.0
	_rescue_remaining = 0.0
	_replan_remaining = 0.0
	state = State.READY
	queue_redraw()


func set_running(running: bool) -> void:
	set_physics_process(running)
	queue_redraw()
	if not running:
		velocity = Vector2.ZERO


func state_text() -> String:
	return State.keys()[state]


func dispatch(person: Survivor) -> bool:
	if state != State.READY or _routes == null or not is_physics_processing() or not can_process():
		return false
	if not is_instance_valid(person) or person.state != Survivor.State.ACTIVE or not person.discovered:
		return false
	_path = _routes.route(global_position, person.global_position)
	if _path.is_empty():
		return false
	target = person
	state = State.TRAVELING
	queue_redraw()
	return true


func _physics_process(delta: float) -> void:
	match state:
		State.TRAVELING, State.RESCUING:
			if not is_instance_valid(target) or target.state != Survivor.State.ACTIVE:
				_begin_return()
			elif state == State.RESCUING:
				_rescue_remaining -= delta
				if _rescue_remaining <= 0.0:
					_pick_up_passengers()
					_begin_return()
			elif global_position.distance_to(target.global_position) <= pickup_radius and _routes.clear_segment(global_position, target.global_position):
				velocity = Vector2.ZERO
				state = State.RESCUING
				_rescue_remaining = rescue_duration
			elif _path.is_empty() or not _follow_path(delta):
				_begin_return()
		State.RETURNING:
			if global_position.distance_to(_berth) < 1.0 and _harbor.contains_point(global_position):
				_unload()
			elif _path.is_empty():
				_replan_remaining -= delta
				if _replan_remaining <= 0.0:
					_path = _routes.route(global_position, _berth)
					_replan_remaining = 1.0
			else:
				_follow_path(delta)
		State.COOLDOWN:
			cooldown_remaining = maxf(0.0, cooldown_remaining - delta)
			if cooldown_remaining <= 0.0:
				state = State.READY
		State.READY:
			return
	queue_redraw()


func _follow_path(delta: float) -> bool:
	var offset := _path[0] - global_position
	velocity = offset.normalized() * speed
	_heading = velocity.angle()
	var collision := move_and_collide(offset.limit_length(speed * delta))
	if collision != null:
		velocity = Vector2.ZERO
		_path.clear()
		return false
	if global_position.distance_to(_path[0]) < 0.1:
		_path.remove_at(0)
	return true


func _pick_up_passengers() -> void:
	if global_position.distance_to(target.global_position) > pickup_radius or not target.pick_up(true):
		return
	passengers.append(target)
	# With extra seats, rescue illuminated or remembered contacts at the same stop.
	for neighbor in target.get_parent().get_children():
		if passengers.size() >= capacity:
			break
		var person := neighbor as Survivor
		if person == null or person.state != Survivor.State.ACTIVE or not person.discovered:
			continue
		if global_position.distance_to(person.global_position) <= pickup_radius and _routes.clear_segment(global_position, person.global_position) and person.pick_up(true):
			passengers.append(person)


func _begin_return() -> void:
	target = null
	velocity = Vector2.ZERO
	state = State.RETURNING
	_path = _routes.route(global_position, _berth)
	_replan_remaining = 1.0


func _unload() -> void:
	velocity = Vector2.ZERO
	_path.clear()
	var manifest: Array[Survivor] = passengers.duplicate()
	passengers.clear()
	if manifest.is_empty():
		state = State.READY
		return
	cooldown_remaining = cooldown_duration
	state = State.COOLDOWN if cooldown_remaining > 0.0 else State.READY
	for person in manifest:
		person.deliver()
	delivered.emit(manifest.size())


func _draw() -> void:
	if is_instance_valid(target) and target.state == Survivor.State.ACTIVE and target.discovered:
		var position_on_map := to_local(target.global_position)
		for quarter in range(4):
			var angle := quarter * PI * 0.5
			draw_arc(position_on_map, 15.0, angle, angle + 0.9, 8, ACCENT, 2.0, true)
	draw_set_transform(Vector2.ZERO, _heading)
	var hull := PackedVector2Array([Vector2(15, 0), Vector2(6, -8), Vector2(-12, -8), Vector2(-14, 0), Vector2(-12, 8), Vector2(6, 8)])
	draw_colored_polygon(hull, ACCENT)
	draw_rect(Rect2(-8, -5, 13, 10), Color("354554"))
	draw_line(Vector2(-6, 0), Vector2(3, 0), Color.WHITE, 2.0)
	draw_line(Vector2(-1.5, -4), Vector2(-1.5, 4), Color.WHITE, 2.0)
	if not passengers.is_empty():
		draw_circle(Vector2(8, 0), 2.5, Color.WHITE)
	draw_set_transform(Vector2.ZERO)
