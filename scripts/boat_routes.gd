extends RefCounted
## Visibility graph for the level's static colliders. Every edge must fit the hull.

const CIRCLE_STEPS := 12
const CLEARANCE := 2.0

var _boat: CharacterBody2D
var _world: Node2D
var _radius: float
var _graph := AStar2D.new()
var _built := false


func _init(boat: CharacterBody2D, world: Node2D, hull_radius: float) -> void:
	_boat = boat
	_world = world
	_radius = hull_radius


func clear_segment(start: Vector2, finish: Vector2) -> bool:
	var pose := _boat.global_transform
	pose.origin = start
	return not _boat.test_move(pose, finish - start, null, 0.15, true)


func route(start: Vector2, finish: Vector2) -> PackedVector2Array:
	if clear_segment(start, finish):
		return PackedVector2Array([finish])
	if not _built:
		_build_graph()
	var start_id := _add_endpoint(start)
	var finish_id := _add_endpoint(finish)
	var path := _graph.get_point_path(start_id, finish_id)
	_graph.remove_point(start_id)
	_graph.remove_point(finish_id)
	if not path.is_empty():
		path.remove_at(0)
	return path


func _add_endpoint(point: Vector2) -> int:
	var neighbors := _graph.get_point_ids()
	var id := _graph.get_available_point_id()
	_graph.add_point(id, point)
	for other in neighbors:
		if clear_segment(point, _graph.get_point_position(other)):
			_graph.connect_points(id, other)
	return id


func _build_graph() -> void:
	_built = true
	for node in _world.find_children("*", "CollisionShape2D", true, false):
		var collider := node as CollisionShape2D
		var body := collider.get_parent() as StaticBody2D
		if collider.disabled or body == null or (body.collision_layer & _boat.collision_mask) == 0:
			continue
		if collider.shape is CircleShape2D:
			var circle := collider.shape as CircleShape2D
			var scale_factor := collider.global_scale.abs()
			# Tangent chords between adjacent vertices clear the rock plus the hull.
			var radius := (circle.radius * maxf(scale_factor.x, scale_factor.y) + _radius + CLEARANCE) / cos(PI / CIRCLE_STEPS)
			for step in range(CIRCLE_STEPS):
				var point := collider.global_position + Vector2.from_angle(TAU * step / CIRCLE_STEPS) * radius
				_add_waypoint(point)
		elif collider.shape is RectangleShape2D:
			var rectangle := collider.shape as RectangleShape2D
			var half_size := rectangle.size * 0.5 * collider.global_scale.abs() + Vector2.ONE * (_radius + CLEARANCE)
			for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				var offset: Vector2 = half_size * corner
				_add_waypoint(collider.global_position + offset.rotated(collider.global_rotation))


func _add_waypoint(point: Vector2) -> void:
	# Another rock or the boundary can cover a candidate on a nearby shape.
	if clear_segment(point, point):
		_add_endpoint(point)
