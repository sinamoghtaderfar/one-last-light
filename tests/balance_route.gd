extends SceneTree
## Reproduce with --headless --fixed-fps 60 --script res://tests/balance_route.gd.
## Keys steer an unupgraded boat along authored sea lanes. No actor is teleported.

const KEYS := ["move_left", "move_right", "move_up", "move_down"]
const NORTH_GATE := Vector2(955, 205)
const NORTH_LANE := Vector2(520, 215)
const SOUTH_GATE := Vector2(888, 519)
const SOUTH_LANE := Vector2(655, 519)
const WEST_LANE := Vector2(320, 388)
const MID_GATE := Vector2(875, 380)
const ISLAND_BYPASS := Vector2(595, 405)

# Integers identify a survivor. Vectors are steering marks. Each row ends at harbor.
const STANDARD_TRIPS := [
	[1, 10, MID_GATE],
	[NORTH_GATE, 2, 4, NORTH_GATE],
	[SOUTH_GATE, 14, 3, SOUTH_GATE],
	[SOUTH_GATE, SOUTH_LANE, 13, 9, SOUTH_LANE, SOUTH_GATE],
	[NORTH_GATE, Vector2(770, 169), NORTH_LANE, 5, 12, 5, NORTH_LANE,
		Vector2(770, 169), NORTH_GATE],
	[MID_GATE, ISLAND_BYPASS, WEST_LANE, 11, 7, 11, WEST_LANE, ISLAND_BYPASS, MID_GATE],
	[SOUTH_GATE, SOUTH_LANE, 8, 15, 8, SOUTH_LANE, SOUTH_GATE],
]
const FIRST_SOLO_TRIP := [
	NORTH_GATE, Vector2(770, 169), NORTH_LANE, Vector2(320, 159), 6, 12,
	Vector2(320, 159), NORTH_LANE, Vector2(770, 169), NORTH_GATE,
]

var boat: RescueBoat
var manager: RescueGameManager
var people: Dictionary[int, Survivor] = {}
var min_oxygen: float
var simulation_failed := false
var decision_seconds: float


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if Engine.physics_ticks_per_second != 60:
		push_error("Use the project's default 60 physics ticks per second.")
		quit(1)
		return
	var scene := load("res://scenes/main.tscn") as PackedScene
	for strategy in ["mixed", "solo", "solo_fast_decisions"]:
		var mixed: bool = strategy == "mixed"
		decision_seconds = 1.0 if strategy == "solo_fast_decisions" else 3.0
		var main := scene.instantiate()
		root.add_child(main)
		await physics_frame
		manager = main.get_node("GameManager")
		boat = manager.boat
		people.clear()
		for person in manager.survivors:
			people[person.survivor_id] = person
			person.picked_up.connect(_record_pickup)
		min_oxygen = INF
		manager.start_round()
		# Supply a deterministic pointer bearing in headless mode. The manager still
		# performs its usual cone, memory and proximity detection every frame.
		manager.lighthouse.set_process(false)
		await _survey(6, 4.0)
		if mixed:
			if not manager.dispatch_at(people[6].global_position):
				_fail("The initial illuminated contact could not be dispatched.")
		else:
			await _trip(FIRST_SOLO_TRIP)
		for trip in STANDARD_TRIPS:
			if not manager.round_active or simulation_failed:
				break
			await _trip(trip)
		_release_keys()
		print("BALANCE %s: main=%d emergency=%d lost=%d stars=%d elapsed=%.2fs min_pickup_oxygen=%.2fs" % [
			strategy, manager.main_delivered, manager.emergency_delivered, manager.lost_count,
			manager.stars, manager.elapsed_time, min_oxygen])
		if manager.result != RescueGameManager.Result.VICTORY or manager.rescued_count < 13:
			_fail("The %s reference route must deliver at least 13 within the level clock." % strategy)
		if mixed and manager.emergency_delivered != 1:
			_fail("The mixed reference route must complete its emergency assignment.")
		if strategy != "solo" and manager.rescued_count != people.size():
			_fail("The %s reference route must demonstrate a full unupgraded rescue." % strategy)
		if manager.stars != manager.main_delivered * manager.stars_per_survivor:
			_fail("The star bank must match the observed main-boat deliveries.")
		root.remove_child(main)
		main.free()
		if simulation_failed:
			break
	quit(1 if simulation_failed else 0)


func _trip(stops: Array) -> void:
	_release_keys()
	await _wait_seconds(decision_seconds) # Read oxygen times and choose the next trip.
	for stop in stops:
		if not manager.round_active or simulation_failed:
			return
		if stop is Vector2:
			await _sail(stop, 12.0)
		else:
			var person := people[int(stop)]
			if person.state == Survivor.State.ACTIVE:
				await _survey(person.survivor_id, 0.8)
				await _sail(person.global_position, boat.pickup_radius * 0.7)
				if manager.round_active and person.state == Survivor.State.ACTIVE:
					manager.try_interact()
					if person.state != Survivor.State.ON_MAIN_BOAT:
						_fail("Expected pickup of %02d at %s." % [person.survivor_id, boat.global_position])
			else:
				# Collected contacts can still serve as a known waypoint on the way home.
				await _sail(person.global_position, 20.0)
	if manager.round_active and not simulation_failed:
		await _sail(manager.harbor.global_position, manager.harbor.safe_radius * 0.65)
		_release_keys()
		manager.try_interact()


func _sail(point: Vector2, arrival_radius: float) -> void:
	var deadline := manager.elapsed_time + 24.0
	while manager.round_active and not simulation_failed and boat.global_position.distance_to(point) > arrival_radius:
		if manager.elapsed_time > deadline:
			_fail("Steering stalled at %s on approach to %s." % [boat.global_position, point])
			break
		var bearing := boat.global_position.angle_to_point(point)
		var heading := Vector2.from_angle(snappedf(bearing, PI / 4.0))
		var strengths := [-heading.x, heading.x, -heading.y, heading.y]
		for index in range(KEYS.size()):
			if strengths[index] > 0.5:
				Input.action_press(KEYS[index])
			else:
				Input.action_release(KEYS[index])
		await physics_frame
	_release_keys()


func _survey(id: int, seconds: float) -> void:
	_release_keys()
	for tick in range(roundi(seconds * 60.0)):
		if not manager.round_active:
			break
		manager.lighthouse.aim_at(people[id].global_position, 1.0 / 60.0)
		await physics_frame


func _wait_seconds(seconds: float) -> void:
	for tick in range(roundi(seconds * 60.0)):
		await physics_frame


func _release_keys() -> void:
	for action in KEYS:
		Input.action_release(action)


func _record_pickup(person: Survivor) -> void:
	min_oxygen = minf(min_oxygen, person.oxygen_remaining)


func _fail(message: String) -> void:
	simulation_failed = true
	push_error(message)
