extends SceneTree
## Authoring aid, not a pass/fail test: prints survivor clearances, route lengths and the oxygen each
## level needs. Run: godot --headless --path . --script res://tests/tools/plan_report.gd
## Optional argument after "--": a level number to report on.

## Room kept beside every rock when planning, so wobbling 8-way steering never grazes one.
const ROUTE_MARGIN := 10.0
const SAFETY := {1: 3.0, 2: 1.5, 3: 1.4, 4: 1.3, 5: 1.35}
const ALLOWANCE := {1: 45.0, 2: 25.0, 3: 22.0, 4: 20.0, 5: 25.0}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var scene := load("res://scenes/main.tscn") as PackedScene
	var main := scene.instantiate()
	root.add_child(main)
	await physics_frame
	var manager: RescueGameManager = main.get_node("GameManager")
	var boat: RescueBoat = manager.boat
	var hull := (boat.get_node("CollisionShape2D") as CollisionShape2D).shape as CircleShape2D
	var planner := LevelPlanner.new(RoutePlanner.new(boat, main.get_node("World"), hull.radius, ROUTE_MARGIN), manager.harbor.global_position + Vector2(-38, 0))
	var wanted := 0
	for argument in OS.get_cmdline_user_args():
		wanted = int(argument)
	for level in manager.levels:
		if wanted != 0 and level.level_number != wanted:
			continue
		print("=== LEVEL %d  %s  (%d survivors) ===" % [level.level_number, level.title, level.survivors.size()])
		var people: Array = []
		for spec in level.survivors:
			var clearance := _clearance(main, spec.position)
			var reach := planner.distance(planner.harbor_gate, spec.position)
			print("  #%d at (%d,%d) oxygen %ds  clearance %.0f px  route from harbor %.0f px%s" % [spec.survivor_id, spec.position.x, spec.position.y, spec.oxygen_seconds, clearance, reach, "" if clearance >= 42.0 and reach > 0.0 else "   <-- CHECK"])
			people.append({"id": spec.survivor_id, "position": spec.position, "oxygen": 1000.0})
		var plan := planner.best_plan(people, 1, boat.base_speed, 0.0)
		var suggestion: Array[String] = []
		for person in people:
			var seconds: float = plan["pickup_times"][person["id"]]
			var need: float = ceilf((seconds * SAFETY[level.level_number] + ALLOWANCE[level.level_number]) / 5.0) * 5.0
			suggestion.append("#%d:%d" % [person["id"], need])
		print("  capacity-1 plan %s  total %.0fs   suggested oxygen %s" % [plan["trips"], plan["total_time"], " ".join(suggestion)])
		for spec in level.survivors:
			people[spec.survivor_id - 1]["oxygen"] = spec.oxygen_seconds
		for config in [[1, 1.0], [2, 1.0], [3, 1.0], [4, 1.0], [3, 1.18], [4, 1.18]]:
			var best := planner.best_plan(people, config[0], boat.base_speed * config[1], 0.0)
			print("    capacity %d speed x%.2f: trips %s  total %.0fs  tightest reserve %.1fs" % [config[0], config[1], best["trips"], best["total_time"], best["min_reserve"]])
	quit()


## Smallest gap, in pixels, between the point and any static collider or sea edge.
func _clearance(main: Node, point: Vector2) -> float:
	var smallest := INF
	for node in main.get_node("World").find_children("*", "CollisionShape2D", true, false):
		var collider := node as CollisionShape2D
		if collider.shape is CircleShape2D:
			smallest = minf(smallest, collider.global_position.distance_to(point) - (collider.shape as CircleShape2D).radius)
		elif collider.shape is RectangleShape2D:
			var rect := Rect2(collider.global_position - (collider.shape as RectangleShape2D).size * 0.5, (collider.shape as RectangleShape2D).size)
			var nearest := Vector2(clampf(point.x, rect.position.x, rect.end.x), clampf(point.y, rect.position.y, rect.end.y))
			smallest = minf(smallest, nearest.distance_to(point))
	return smallest
