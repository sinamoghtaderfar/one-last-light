extends SceneTree
## godot --headless --path . --fixed-fps 60 --script res://tests/balance_suite.gd
## Balance proof for the five levels. A bot steers the real boat with the movement actions along
## collision-free routes, aims the beam, presses E and unloads, exactly like a player. The route is
## the best plan from LevelPlanner for the level's real oxygen budgets. Every upgrade state a
## player can actually reach is played, including the ones that skip every purchase.

const KEYS := ["move_left", "move_right", "move_up", "move_down"]
## Upgrade states reachable through the campaign: [capacity, speed level, how the player got there].
const CONFIGS := {
	1: [[1, 0, "no upgrades"]],
	2: [[1, 0, "skipped the Level 1 upgrade"], [2, 0, "bought the Level 1 upgrade"]],
	3: [[1, 0, "no upgrades"], [2, 0, "one capacity upgrade"], [3, 0, "both capacity upgrades"]],
	4: [[1, 0, "no upgrades"], [2, 0, "one capacity upgrade"], [3, 0, "both capacity upgrades"]],
	5: [[1, 0, "no upgrades"], [1, 1, "speed only"], [2, 0, "one capacity upgrade"], [3, 0, "two capacity upgrades, skipped the Level 5 offer"],
		[3, 1, "two capacity upgrades and speed"], [4, 0, "all three capacity upgrades"]],
}
## Planner assumptions that a person cannot beat: a pause to read the timers before every trip.
const DECISION_SECONDS := 3.0
const HARBOR_GATE_OFFSET := Vector2(-38, 0)
## Room kept beside every rock when planning, so wobbling 8-way steering never grazes one.
const ROUTE_MARGIN := 10.0
## How long the bot keeps one key combination pressed before choosing again (a third of a second).
const HOLD_FRAMES := 20
const ROUTE_STEP_RADIUS := 10.0
## Oxygen rules the level files were derived from (see TESTING.md). A level may not fall below them.
const MIN_FIRST_LEVEL_OXYGEN := 120.0

var checks: int = 0
var failures: Array[String] = []
var main: Node
var manager: RescueGameManager
var boat: RescueBoat
var planner: LevelPlanner
var people: Dictionary = {}
var tightest_reserve: float
var bot_failed := false
var steer_phase := 0.0
var hold_frames_left := 0
var held_angle := 0.0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if Engine.physics_ticks_per_second != 60:
		push_error("Use the project's default 60 physics ticks per second.")
		quit(1)
		return
	var scene := load("res://scenes/main.tscn") as PackedScene
	main = scene.instantiate()
	root.add_child(main)
	await physics_frame
	manager = main.get("manager")
	boat = manager.boat
	var hull := (boat.get_node("CollisionShape2D") as CollisionShape2D).shape as CircleShape2D
	planner = LevelPlanner.new(RoutePlanner.new(boat, main.get_node("World"), hull.radius, ROUTE_MARGIN), manager.harbor.global_position + HARBOR_GATE_OFFSET)
	_check_level_data()
	var only := 0 # Optional argument after "--" limits the bot runs to one level while debugging.
	for argument in OS.get_cmdline_user_args():
		only = int(argument)
	for level_index in range(manager.levels.size()):
		if only != 0 and level_index + 1 != only:
			continue
		for config in CONFIGS[level_index + 1]:
			await _play(level_index, config[0], config[1], config[2])
	_finish()


## Geometry and rules every level must satisfy before any bot plays it.
func _check_level_data() -> void:
	_expect(manager.levels.size() == 5, "The campaign has exactly five levels")
	var expected_counts := [1, 2, 4, 5, 6]
	for index in range(manager.levels.size()):
		var level := manager.levels[index]
		var label := "Level %d" % level.level_number
		_expect(level.level_number == index + 1, "%s is numbered in order" % label)
		_expect(level.survivors.size() == expected_counts[index], "%s has exactly %d survivors" % [label, expected_counts[index]])
		var ids := {}
		var spots := {}
		var oxygen := {}
		for spec in level.survivors:
			ids[spec.survivor_id] = true
			spots[spec.position] = true
			oxygen[spec.oxygen_seconds] = true
		_expect(ids.size() == level.survivors.size() and spots.size() == level.survivors.size(), "%s: unique ids and positions" % label)
		_expect(oxygen.size() == level.survivors.size() or level.survivors.size() == 1, "%s: every survivor has an individual oxygen budget" % label)
		_expect(is_equal_approx(level.time_limit, 240.0), "%s keeps the four-minute clock" % label)
		var apart := true
		for a in level.survivors:
			for b in level.survivors:
				if a != b and a.position.distance_to(b.position) < 100.0:
					apart = false
		_expect(apart, "%s: survivors are at least 100 px apart, so their labels never overlap" % label)
		for spec in level.survivors:
			var clearance := _clearance(spec.position)
			_expect(clearance >= 40.0, "%s survivor %d is in open water (%.0f px from the nearest rock, island or edge)" % [label, spec.survivor_id, clearance])
			_expect(manager.harbor.global_position.distance_to(spec.position) > 120.0 and spec.position.distance_to(manager.lighthouse.global_position) > 120.0,
				"%s survivor %d is clear of the harbor and the lighthouse" % [label, spec.survivor_id])
			var reachable := planner.routes.route(planner.harbor_gate, spec.position)
			_expect(not reachable.is_empty() and reachable[reachable.size() - 1].is_equal_approx(spec.position), "%s survivor %d is reachable by a collision-free route" % [label, spec.survivor_id])
	var level_one := manager.levels[0].survivors[0]
	_expect(planner.distance(planner.harbor_gate, level_one.position) >= 600.0, "Level 1's survivor is far from the harbor")
	_expect(level_one.oxygen_seconds >= MIN_FIRST_LEVEL_OXYGEN, "Level 1 gives a new player at least %d seconds of oxygen" % MIN_FIRST_LEVEL_OXYGEN)
	_expect(manager.levels[0].show_mouse_cue and not manager.levels[1].show_mouse_cue and not manager.levels[4].show_mouse_cue, "Only Level 1 carries the mouse cue")
	_expect(manager.economy.starting_capacity == 1 and boat.initial_capacity == 1, "The boat and the economy both start with capacity 1")


func _play(level_index: int, capacity: int, speed_level: int, label: String) -> void:
	var level := manager.levels[level_index]
	manager.economy.reset_campaign()
	manager.economy.capacity = capacity # Test fixture: the upgrade state the player reached.
	manager.economy.speed_level = speed_level
	manager.load_level(level_index)
	people.clear()
	for person in manager.survivors:
		people[person.survivor_id] = person
		person.picked_up.connect(_record_pickup)
	tightest_reserve = INF
	bot_failed = false
	manager.start_round()
	# Supply a deterministic beam bearing in headless mode. The manager still runs its usual
	# cone, memory and proximity detection every frame.
	manager.lighthouse.set_process(false)
	var speed := boat.base_speed * boat.speed_multiplier
	var list: Array = []
	for spec in level.survivors:
		list.append({"id": spec.survivor_id, "position": spec.position, "oxygen": spec.oxygen_seconds})
	var plan := planner.best_plan(list, capacity, speed, 0.0)
	var description := "Level %d, capacity %d, speed %+d%% (%s)" % [level.level_number, capacity, roundi(speed_level * boat.speed_bonus_per_level * 100), label]
	_expect(boat.capacity == capacity, "%s: the boat starts the level with the carried-over capacity" % description)
	_expect(not plan.is_empty() and plan["min_reserve"] > 0.0, "%s: the planner finds a rescue order that beats every oxygen budget" % description)
	if plan.is_empty():
		return
	for trip in plan["trips"]:
		if not manager.round_active or bot_failed:
			break
		await _trip(trip)
	_release_keys()
	var delivered := manager.delivered_count
	print("BALANCE %s: delivered %d/%d, lost %d, elapsed %.1fs of %.0fs, tightest oxygen reserve at pickup %.1fs, plan %s" % [
		description, delivered, level.survivors.size(), manager.lost_count, manager.elapsed_time, level.time_limit, tightest_reserve, str(plan["trips"])])
	_expect(manager.result == RescueGameManager.Result.VICTORY and delivered == level.survivors.size() and manager.lost_count == 0,
		"%s: the bot delivers every survivor" % description)
	_expect(manager.elapsed_time < level.time_limit * 0.6, "%s: and finishes with at least 40%% of the clock to spare (%.0f s used)" % [description, manager.elapsed_time])
	_expect(tightest_reserve >= 8.0, "%s: no survivor is picked up with under 8 s of oxygen left (tightest %.1f s)" % [description, tightest_reserve])
	_expect(manager.level_stars == delivered * manager.stars_per_survivor, "%s: stars match deliveries" % description)


func _trip(ids: Array) -> void:
	_release_keys()
	await _wait_seconds(DECISION_SECONDS)
	for id in ids:
		if not manager.round_active or bot_failed:
			return
		var person: Survivor = people[id]
		await _survey(person, 0.8)
		await _go(person.global_position, boat.pickup_radius * 0.7)
		if manager.round_active and person.state == Survivor.State.ACTIVE:
			manager.try_interact()
			if person.state != Survivor.State.ON_BOAT:
				_fail("Expected pickup of %02d at %s." % [id, boat.global_position])
	if manager.round_active and not bot_failed:
		await _go(planner.harbor_gate, 8.0)
		_release_keys()
		manager.try_interact()


## Follows the collision-free route waypoint by waypoint with 8-way keyboard steering.
func _go(target: Vector2, final_radius: float) -> void:
	var path := planner.routes.route(boat.global_position, target)
	for index in range(path.size()):
		var last := index == path.size() - 1
		await _sail(path[index], final_radius if last else ROUTE_STEP_RADIUS)


func _sail(point: Vector2, arrival_radius: float) -> void:
	var deadline := manager.elapsed_time + 30.0
	while manager.round_active and not bot_failed and boat.global_position.distance_to(point) > arrival_radius:
		if manager.elapsed_time > deadline:
			_fail("Steering stalled at %s on approach to %s." % [boat.global_position, point])
			break
		# Eight-way keyboard steering. A player holds a key pair for a moment, so the bot picks one of
		# the two neighbouring compass headings and holds it for HOLD_FRAMES. Alternating them in the
		# proportion that averages to the true bearing keeps the boat on its route.
		if hold_frames_left <= 0:
			var bearing := boat.global_position.angle_to_point(point)
			var lower := floorf(bearing / (PI / 4.0)) * (PI / 4.0)
			steer_phase += (bearing - lower) / (PI / 4.0)
			held_angle = lower
			if steer_phase >= 1.0:
				held_angle = lower + PI / 4.0
				steer_phase -= 1.0
			hold_frames_left = HOLD_FRAMES
		hold_frames_left -= 1
		var heading := Vector2.from_angle(held_angle)
		var strengths := [-heading.x, heading.x, -heading.y, heading.y]
		for index in range(KEYS.size()):
			if strengths[index] > 0.5:
				Input.action_press(KEYS[index])
			else:
				Input.action_release(KEYS[index])
		await physics_frame
	_release_keys()


func _survey(person: Survivor, seconds: float) -> void:
	_release_keys()
	for tick in range(roundi(seconds * 60.0)):
		if not manager.round_active:
			break
		manager.lighthouse.aim_at(person.global_position, 1.0 / 60.0)
		await physics_frame


func _wait_seconds(seconds: float) -> void:
	for tick in range(roundi(seconds * 60.0)):
		await physics_frame


func _release_keys() -> void:
	for action in KEYS:
		Input.action_release(action)


func _record_pickup(person: Survivor) -> void:
	tightest_reserve = minf(tightest_reserve, person.oxygen_remaining)


func _fail(message: String) -> void:
	bot_failed = true
	failures.append(message)
	push_error(message)


## Smallest gap, in pixels, between the point and any static collider or sea edge.
func _clearance(point: Vector2) -> float:
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


func _expect(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("PASS: " + description)
	else:
		failures.append(description)
		push_error("FAIL: " + description)


func _finish() -> void:
	_release_keys()
	print("BALANCE SUITE: %d/%d checks passed" % [checks - failures.size(), checks])
	if is_instance_valid(main):
		main.queue_free()
	quit(0 if failures.is_empty() else 1)
