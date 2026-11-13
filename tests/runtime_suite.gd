extends SceneTree
## Run after import: godot --headless --path . --script res://tests/runtime_suite.gd
## Exercises real scenes, signals, input, physics, and two complete rescue rounds.

var checks: int = 0
var failures: Array[String] = []
var main: Node
var manager: RescueGameManager
var boat: RescueBoat
var lighthouse: Lighthouse
var harbor: Harbor
var people: Array[Survivor] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var scene := load("res://scenes/main.tscn") as PackedScene
	_expect(scene != null, "Main scene loads")
	if scene == null:
		_finish()
		return
	main = scene.instantiate()
	root.add_child(main)
	await process_frame
	manager = main.get("manager") as RescueGameManager
	boat = main.get("boat") as RescueBoat
	lighthouse = main.get("lighthouse") as Lighthouse
	harbor = main.get("harbor") as Harbor
	_expect(manager != null and boat != null and lighthouse != null and harbor != null,
		"Main scene resolves all gameplay components")
	if manager == null or boat == null or lighthouse == null or harbor == null:
		_finish()
		return
	people.assign(manager.survivors)
	_expect(people.size() == 10, "Level contains ten survivors")
	_expect(ProjectSettings.get_setting("application/run/main_scene") == "res://scenes/main.tscn",
		"Project main scene is configured")
	_expect(ProjectSettings.get_setting("rendering/renderer/rendering_method") == "gl_compatibility",
		"Compatibility renderer is configured")
	_expect(not manager.round_active and not boat.controls_enabled and not lighthouse.enabled,
		"Briefing freezes gameplay")
	var initial_oxygen: float = people[0].oxygen_remaining
	await _frames(4)
	_expect(is_equal_approx(initial_oxygen, people[0].oxygen_remaining), "Oxygen waits for launch")
	var durations: Dictionary = {}
	for person in people:
		durations[person.oxygen_duration] = true
	_expect(durations.size() > 1, "Survivors have different configurable oxygen budgets")

	manager.start_round()
	_expect(manager.round_active and boat.controls_enabled and lighthouse.enabled,
		"Launch activates the rescue round")
	_expect(boat.capacity == 3 and boat.passengers.is_empty(), "Boat begins with three empty seats")
	_expect(not manager.buy_capacity_upgrade(), "Upgrades cannot be bought during a round")

	# The entire world, including countdowns and steering, must pause together.
	paused = true
	initial_oxygen = people[0].oxygen_remaining
	var initial_angle: float = lighthouse.beam_angle
	Input.action_press("move_left")
	var paused_position: Vector2 = boat.global_position
	await _frames(8)
	_expect(is_equal_approx(initial_oxygen, people[0].oxygen_remaining), "Pause freezes oxygen")
	_expect(is_equal_approx(initial_angle, lighthouse.beam_angle), "Pause freezes lighthouse")
	_expect(boat.global_position.is_equal_approx(paused_position), "Pause freezes boat movement")
	Input.action_release("move_left")
	paused = false

	# Keep simulation deterministic while testing individual transitions.
	manager.set_process(false)
	lighthouse.set_process(false)
	for person in people:
		person.set_process(false)
	await _physics_frames(2)
	boat.global_position = Vector2(2000, 2000)
	boat.velocity = Vector2.ZERO
	Input.action_press("move_right")
	await _physics_frames(10)
	_expect(boat.global_position.x > 2000, "Movement input moves the CharacterBody2D")
	_expect(boat.velocity.x > 0 and boat.velocity.x < boat.base_speed,
		"Acceleration ramps toward maximum speed")
	Input.action_release("move_right")
	await _physics_frames(25)
	_expect(boat.velocity.length() < 0.1, "Deceleration brings the boat to rest")

	# Instantiate the actual editable rock scene and move into it using real physics.
	var rock_scene := load("res://scenes/rock.tscn") as PackedScene
	var rock := rock_scene.instantiate() as NavigationRock
	root.add_child(rock)
	rock.global_position = Vector2(2110, 2000)
	boat.global_position = Vector2(2020, 2000)
	boat.velocity = Vector2.ZERO
	await _physics_frames(2)
	Input.action_press("move_right")
	await _physics_frames(70)
	Input.action_release("move_right")
	_expect(boat.global_position.x < rock.global_position.x - rock.radius,
		"Rock collision blocks sustained boat movement")
	_expect(boat.get_slide_collision_count() > 0, "Boat reports a real rock slide collision")
	rock.queue_free()
	boat.global_position = lighthouse.global_position + Vector2(-110, 0)
	boat.velocity = Vector2.ZERO
	await _physics_frames(2)
	_expect(boat.test_move(boat.global_transform, Vector2(120, 0)),
		"Lighthouse island has an actual blocking collider")

	initial_angle = lighthouse.beam_angle
	lighthouse._process(0.5)
	_expect(not is_equal_approx(initial_angle, lighthouse.beam_angle), "Lighthouse beam rotates")
	var beam_point: Vector2 = lighthouse.global_position + Vector2.from_angle(lighthouse.beam_angle) * 200
	_expect(lighthouse.is_illuminated(beam_point), "Beam detects an in-cone survivor position")
	_expect(not lighthouse.is_illuminated(lighthouse.global_position - Vector2.from_angle(lighthouse.beam_angle) * 200),
		"Beam rejects positions outside its cone")
	_expect(not lighthouse.is_illuminated(lighthouse.global_position + Vector2.from_angle(lighthouse.beam_angle) * (lighthouse.beam_length + 5)),
		"Beam range is finite")
	people[0].discovered = false
	lighthouse.beam_angle = (people[0].global_position - lighthouse.global_position).angle()
	manager._process(0.0)
	_expect(people[0].discovered, "Manager discovers a survivor illuminated by the lighthouse")
	lighthouse.beam_angle += PI
	manager._process(0.0)
	_expect(people[0].discovered, "Discovery marker persists after the beam passes")

	boat.set_physics_process(false)
	boat.global_position = Vector2(780, 510)
	boat.velocity = Vector2.ZERO
	for index in range(people.size()):
		people[index].global_position = Vector2(120 + index * 45, 160)
		people[index].discovered = false
	initial_oxygen = people[0].oxygen_remaining
	people[0]._process(1.0)
	_expect(is_equal_approx(people[0].oxygen_remaining, initial_oxygen - 1.0),
		"Oxygen decreases while a survivor remains in water")
	people[0].global_position = boat.global_position
	_expect(not boat.try_board(people[0]), "Undiscovered survivors cannot be boarded")
	for index in range(3):
		people[index].global_position = boat.global_position
		people[index].discover()
		manager.try_interact()
		_expect(people[index].state == Survivor.State.RESCUED, "E boards survivor %d" % (index + 1))
	initial_oxygen = people[0].oxygen_remaining
	people[0]._process(20.0)
	_expect(is_equal_approx(initial_oxygen, people[0].oxygen_remaining), "Oxygen stops after boarding")
	_expect(manager.rescued_count == 0 and manager.stars == 0,
		"Boarding alone gives no successful rescue credit or currency")
	people[3].global_position = boat.global_position
	people[3].discover()
	manager.try_interact()
	_expect(boat.passengers.size() == 3 and people[3].state == Survivor.State.ACTIVE,
		"Capacity prevents a fourth passenger from boarding")
	_expect(manager.context_hint().contains("FULL"), "Full boat gets a contextual return instruction")

	boat.global_position = harbor.global_position
	_expect(harbor.contains_point(boat.global_position), "Harbor recognizes its safe zone")
	manager.try_interact()
	_expect(boat.passengers.is_empty() and manager.rescued_count == 3,
		"Harbor E interaction delivers all three passengers and frees capacity")
	_expect(manager.stars == 3 * manager.stars_per_survivor, "Only delivered passengers award stars")
	_expect(people[0].state == Survivor.State.TRANSPORTED, "Delivery sets transported state")
	manager.try_interact()
	_expect(manager.rescued_count == 3 and manager.stars == 9, "Empty unload cannot duplicate rescue rewards")
	people[3].oxygen_remaining = 0.01
	people[3]._process(0.02)
	_expect(people[3].state == Survivor.State.LOST and manager.lost_count == 1,
		"Oxygen exhaustion signals loss and updates accounting")
	_expect(not people[3].pick_up(), "Lost survivors cannot be picked up")
	_expect(manager.round_active, "Round continues while active water contacts remain")
	_lose_all_active()
	_expect(not manager.round_active and not boat.controls_enabled, "Resolved round ends and freezes controls")
	_expect(manager.rescued_count + manager.lost_count == 10, "End results account for all ten people")
	var previous_stars: int = manager.stars
	var capacity_price: int = manager.capacity_cost()
	_expect(manager.buy_capacity_upgrade(), "Earned stars purchase a capacity upgrade between rounds")
	_expect(manager.stars == previous_stars - capacity_price and boat.capacity == 4,
		"Capacity purchase deducts the configured cost and adds a real seat")
	_expect(not manager.buy_speed_upgrade(), "Insufficient stars prevent a purchase")

	# A second complete round tests progression and waiting for final delivery.
	manager.next_round()
	for person in people:
		person.set_process(false)
	lighthouse.set_process(false)
	_expect(manager.round_index == 2 and boat.capacity == 4,
		"Next round preserves upgrades and increments round index")
	_expect(manager.rescued_count == 0 and manager.lost_count == 0 and manager.active_count() == 10,
		"Next round resets survivor states and result counters")
	boat.global_position = Vector2(780, 510)
	for index in range(people.size()):
		people[index].global_position = Vector2(120 + index * 45, 160)
	for index in range(4):
		people[index].global_position = boat.global_position
		people[index].discover()
		manager.try_interact()
	_expect(boat.passengers.size() == 4, "Upgraded fourth seat works in the next round")
	_lose_all_active()
	manager.finish_round()
	_expect(manager.active_count() == 0 and manager.round_active,
		"Round remains active when the final survivors are aboard awaiting delivery")
	boat.global_position = harbor.global_position
	manager.try_interact()
	_expect(not manager.round_active and manager.rescued_count == 4,
		"Delivering the final passengers ends the round")
	previous_stars = manager.stars
	var speed_price: int = manager.speed_cost()
	_expect(manager.buy_speed_upgrade(), "Second-round rewards buy a speed upgrade")
	_expect(manager.stars == previous_stars - speed_price and boat.speed_multiplier > 1.0,
		"Speed upgrade charges stars and increases actual movement multiplier")
	previous_stars = manager.stars
	manager.restart_round()
	_expect(manager.round_index == 2 and manager.round_active and manager.stars == previous_stars,
		"Restart resets the round while keeping earned currency")
	_expect(boat.capacity == 4 and boat.speed_multiplier > 1.0 and manager.active_count() == 10,
		"Restart retains upgrades and restores all survivors")
	_finish()


func _lose_all_active() -> void:
	for person in people:
		if person.state == Survivor.State.ACTIVE:
			person.oxygen_remaining = 0.001
			person._process(0.01)


func _frames(count: int) -> void:
	for index in range(count):
		await process_frame


func _physics_frames(count: int) -> void:
	for index in range(count):
		await physics_frame


func _expect(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("PASS: " + description)
	else:
		failures.append(description)
		push_error("FAIL: " + description)


func _finish() -> void:
	Input.action_release("move_left")
	Input.action_release("move_right")
	print("RUNTIME SUITE: %d/%d checks passed" % [checks - failures.size(), checks])
	if is_instance_valid(main):
		main.queue_free()
	quit(0 if failures.is_empty() else 1)
