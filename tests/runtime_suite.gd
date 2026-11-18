extends SceneTree
## godot --headless --fixed-fps 60 --path . --script res://tests/runtime_suite.gd
## Core gameplay on the real scene: level start state, steering and collisions, lighthouse
## discovery, oxygen, pickup, capacity, delivery, pause, win and fail rules, retry, and the HUD.
## Multi-seat sections load Level 3 (four survivors) with a capacity fixture; Level 1 is used as
## shipped. Fixtures are marked "(setup)".

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
		"Main scene resolves the boat, manager, lighthouse and harbor")
	if not manager or not boat or not lighthouse or not harbor:
		_finish()
		return
	_refresh_people()
	await _check_level()
	await _check_movement()
	_check_discovery()
	await _check_single_seat_rescue()
	await _check_multi_seat_rescue()
	await _check_pause()
	await _check_failures_and_retry()
	await _check_victory_rules()
	_check_hud()
	_finish()


func _refresh_people() -> void:
	people.assign(manager.survivors)


## Fixture: load a level with the boat carrying the given capacity, and start it at once.
func _start_level(level_number: int, capacity: int = 1) -> void:
	manager.economy.reset_campaign()
	manager.economy.capacity = capacity # (setup) the upgrade state the player arrived with
	manager.load_level(level_number - 1)
	_refresh_people()
	manager.start_round()


func _check_level() -> void:
	_expect(ProjectSettings.get_setting("application/run/main_scene") == "res://scenes/main.tscn",
		"Project main scene is configured")
	_expect(ProjectSettings.get_setting("rendering/renderer/rendering_method") == "gl_compatibility",
		"Compatibility renderer is configured")
	_expect(people.size() == 1 and manager.level_number == 1 and manager.survivors_total == 1, "The game starts on Level 1 with a single survivor")
	var ids := {}
	var positions := {}
	for person in people:
		ids[person.survivor_id] = true
		positions[person.global_position] = true
	_expect(ids.size() == people.size() and positions.size() == people.size(), "Every survivor has a unique ID and position")
	_expect(not manager.round_active and not boat.controls_enabled and not lighthouse.enabled,
		"Briefing freezes gameplay")
	var initial_oxygen := people[0].oxygen_remaining
	await _physics_frames(4)
	_expect(is_equal_approx(initial_oxygen, people[0].oxygen_remaining), "Oxygen waits for launch")
	manager.start_round()
	_expect(manager.round_active and boat.controls_enabled and lighthouse.enabled, "Launch activates the round")
	_expect(boat.capacity == 1 and boat.passengers.is_empty(), "The boat begins with one empty seat")
	_expect(harbor.contains_point(boat.global_position), "The boat starts at the safe harbor")
	_expect(is_equal_approx(manager.level.time_limit, 240.0) and is_equal_approx(manager.time_remaining, 240.0),
		"Level 1 has a four-minute deadline")
	_expect(main.find_child("EmergencyBoat", true, false) == null, "There is no emergency boat in the scene")
	var first_offer := manager.level.upgrade_offers[0]
	_expect(not manager.purchase_offer(first_offer.id), "Upgrades cannot be bought during a round")


func _check_movement() -> void:
	# Open water outside the chart isolates acceleration from map collisions.
	boat.global_position = Vector2(2000, 2000)
	Input.action_press("move_right")
	await _physics_frames(5)
	_expect(boat.global_position.x > 2000, "Movement input moves the CharacterBody2D")
	_expect(boat.velocity.x > 0 and boat.velocity.x < boat.base_speed, "Acceleration ramps toward maximum speed")
	Input.action_release("move_right")
	await _physics_frames(25)
	_expect(boat.velocity.length() < 0.1, "Deceleration brings the boat to rest")

	var rock_scene := load("res://scenes/rock.tscn") as PackedScene
	var rock := rock_scene.instantiate() as NavigationRock
	root.add_child(rock)
	rock.global_position = Vector2(2110, 2000)
	boat.global_position = Vector2(2020, 2000)
	boat.velocity = Vector2.ZERO
	await _physics_frames(2)
	Input.action_press("move_right")
	await _physics_frames(90)
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
	boat.global_position = manager.boat_spawn


func _check_discovery() -> void:
	# The normal process path must read the mouse and turn smoothly, then hold a stationary bearing.
	var mouse_direction := lighthouse.global_position.direction_to(lighthouse.get_global_mouse_position()).angle()
	lighthouse.beam_angle = mouse_direction + PI / 2
	lighthouse._process(1.0 / 60.0)
	var difference := absf(angle_difference(lighthouse.beam_angle, mouse_direction))
	_expect(difference < PI / 2 and difference > 0.0, "Lighthouse smoothly turns toward the actual mouse position")
	lighthouse._process(2.0)
	lighthouse._process(0.1)
	_expect(absf(angle_difference(lighthouse.beam_angle, mouse_direction)) < 0.001,
		"A stationary cursor holds the beam without an automatic sweep")

	var person := people[0]
	var offset := lighthouse.global_position.direction_to(person.global_position)
	lighthouse.aim_at(person.global_position, 2.0)
	_expect(lighthouse.is_illuminated(person.global_position), "Beam detects an in-cone survivor")
	_expect(not lighthouse.is_illuminated(lighthouse.global_position - offset * 100.0), "Beam rejects off-cone positions")
	_expect(not lighthouse.is_illuminated(lighthouse.global_position + offset * (lighthouse.beam_length + 5.0)),
		"Beam range is finite")
	manager._process(0.0)
	_expect(person.discovered and person.visible, "Illumination reveals the survivor and oxygen display")
	lighthouse.aim_at(lighthouse.global_position - offset * 100.0, 2.0)
	manager._process(2.95)
	_expect(person.visible, "Survivor stays visible for the first 2.95 seconds out of the beam")
	manager._process(0.06)
	_expect(not person.discovered and not person.visible, "Survivor hides after three seconds")
	lighthouse.aim_at(person.global_position, 2.0)
	manager._process(0.0)
	_expect(person.discovered and person.visible, "Re-illumination immediately reveals the survivor")


func _check_single_seat_rescue() -> void:
	_start_level(3, 1)
	var first := people[0]
	var second := people[1]
	var initial_oxygen := first.oxygen_remaining
	first._process(1.0)
	_expect(is_equal_approx(first.oxygen_remaining, initial_oxygen - 1.0), "Oxygen decreases in the water")
	boat.global_position = first.global_position
	_expect(not first.discovered and not first.visible, "Contact begins unseen even at the pickup location")
	_key(KEY_E)
	_expect(first.state == Survivor.State.ON_BOAT and boat.passengers.has(first),
		"E boards a nearby survivor before any lighthouse or proximity detection tick")
	initial_oxygen = first.oxygen_remaining
	first._process(20.0)
	_expect(is_equal_approx(initial_oxygen, first.oxygen_remaining), "Oxygen stops on the boat")
	_expect(manager.delivered_count == 0 and manager.stars == 0, "Pickup alone gives no successful rescue or currency")
	boat.global_position = second.global_position
	_key(KEY_E)
	_expect(boat.passengers.size() == 1 and second.state == Survivor.State.ACTIVE, "Capacity 1 prevents a second passenger")
	_expect("FULL" in manager.context_hint().to_upper(), "Full boat gets a return instruction")
	boat.global_position = harbor.global_position
	_key(KEY_E)
	_expect(boat.passengers.is_empty() and manager.delivered_count == 1 and first.state == Survivor.State.DELIVERED,
		"Harbor E unloads the seat and credits the rescue")
	_expect(manager.stars == 3 and manager.stars_per_survivor == 3, "Each delivery earns three stars")
	_key(KEY_E)
	_expect(manager.delivered_count == 1 and manager.stars == 3, "Empty unload cannot duplicate rewards")


func _check_multi_seat_rescue() -> void:
	_start_level(3, 2)
	var one := people[0]
	var two := people[1]
	var three := people[2]
	boat.global_position = one.global_position
	_key(KEY_E)
	lighthouse.aim_at(2.0 * lighthouse.global_position - two.global_position, 2.0)
	boat.global_position = two.global_position + Vector2(0, boat.pickup_radius * 0.8)
	manager._process(0.0)
	_expect(two.visible and not lighthouse.is_illuminated(two.global_position), "Proximity makes an unlit contact visible")
	_key(KEY_E)
	_expect(two.state == Survivor.State.ON_BOAT and boat.passengers.size() == 2, "E fills the second seat")
	boat.global_position = three.global_position
	_key(KEY_E)
	_expect(boat.passengers.size() == 2 and three.state == Survivor.State.ACTIVE, "Capacity 2 prevents a third passenger")
	boat.global_position = harbor.global_position
	_key(KEY_E)
	_expect(boat.passengers.is_empty() and manager.delivered_count == 2 and manager.stars == 6,
		"Harbor E unloads both seats and credits both rescues (6 stars)")
	_expect(manager.economy.stars == 0 and manager.economy.pending_stars == 6,
		"Stars of an unfinished level stay pending until the level is won")


func _check_pause() -> void:
	_start_level(1, 1)
	var person := people[0]
	_key(KEY_ESCAPE)
	_expect(paused, "Escape pauses the gameplay tree")
	var oxygen := person.oxygen_remaining
	var remaining := manager.time_remaining
	var angle := lighthouse.beam_angle
	var boat_position := boat.global_position
	Input.action_press("move_left")
	await _physics_frames(8)
	_expect(is_equal_approx(oxygen, person.oxygen_remaining) and is_equal_approx(remaining, manager.time_remaining),
		"Pause freezes oxygen and level time")
	_expect(is_equal_approx(angle, lighthouse.beam_angle) and boat.global_position.is_equal_approx(boat_position), "Pause freezes the lighthouse and boat")
	Input.action_release("move_left")
	_key(KEY_ESCAPE)
	await _physics_frames(3)
	_expect(not paused and person.oxygen_remaining < oxygen and manager.time_remaining < remaining,
		"Escape resumes the clock and oxygen")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_RIGHT
	click.position = person.get_global_transform_with_canvas().origin
	click.pressed = true
	root.push_input(click, true)
	_expect(not paused and person.state == Survivor.State.ACTIVE and boat.passengers.is_empty(), "Right-click does nothing: there is no dispatch")


func _check_failures_and_retry() -> void:
	_start_level(3, 1)
	var first := people[0]
	_lose(first)
	_expect(first.state == Survivor.State.LOST and manager.lost_count == 1, "Oxygen exhaustion signals one loss")
	_expect(not first.pick_up(), "Lost survivors reject pickup")
	_expect(not manager.round_active and manager.result == RescueGameManager.Result.SURVIVOR_LOST,
		"A single loss makes the level impossible, so it fails immediately")
	_expect(_menu_contains("LEVEL 3 FAILED") and _menu_contains("Survivor 01 was lost"), "The failure screen names the level and the lost survivor")
	_expect(not boat.controls_enabled and not lighthouse.enabled, "Failure disables steering and lighthouse control")
	var oxygen := people[1].oxygen_remaining
	var remaining := manager.time_remaining
	await _physics_frames(4)
	_expect(is_equal_approx(oxygen, people[1].oxygen_remaining) and is_equal_approx(remaining, manager.time_remaining),
		"Results freeze the unresolved contacts and the level clock")

	# A timeout with a living passenger aboard is a failure: aboard is not delivered.
	manager.replay_level()
	manager.begin_round()
	boat.global_position = people[0].global_position
	_key(KEY_E)
	_expect(boat.passengers.size() == 1, "(setup) one survivor is aboard when the clock runs out")
	manager._process(manager.time_remaining)
	_expect(not manager.round_active and manager.time_remaining == 0.0 and manager.result == RescueGameManager.Result.TIME_RAN_OUT,
		"Countdown expiry is a distinct failure even with a living passenger aboard")
	_expect(_menu_contains("Time ran out"), "Timeout screen explains the deadline")
	_expect(manager.delivered_count == 0 and manager.economy.stars == 0 and manager.economy.pending_stars == 0, "A failed level banks nothing")
	manager.replay_level()
	manager.begin_round()
	_expect(manager.round_active and manager.level_number == 3 and manager.result == RescueGameManager.Result.NONE and manager.time_remaining == manager.level.time_limit,
		"Replay restores the clock and clears the result")
	_expect(manager.delivered_count == 0 and manager.lost_count == 0, "Replay clears round statistics")
	var clean := true
	for survivor in manager.survivors:
		clean = clean and survivor.state == Survivor.State.ACTIVE and not survivor.discovered and not survivor.visible and is_equal_approx(survivor.oxygen_remaining, survivor.oxygen_duration)
	_expect(clean and manager.survivors.size() == 4, "Replay resets all four oxygen tanks, states and markers")
	_expect(boat.passengers.is_empty() and harbor.contains_point(boat.global_position), "Replay clears the manifest and returns the boat")


func _check_victory_rules() -> void:
	# Clearing the water is not a win: a passenger who is aboard still has to be delivered.
	_start_level(3, 4)
	for person in people:
		boat.global_position = person.global_position
		_key(KEY_E)
	_expect(manager.active_count() == 0 and boat.passengers.size() == 4 and manager.round_active and manager.result == RescueGameManager.Result.NONE,
		"Everyone aboard and nobody in the water is not yet a victory")
	boat.global_position = harbor.global_position
	_key(KEY_E)
	_expect(manager.result == RescueGameManager.Result.VICTORY and manager.delivered_count == 4 and manager.lost_count == 0,
		"Delivering the last passenger wins the level")
	_expect(manager.level_stars == 12 and manager.economy.stars == 12 and manager.economy.pending_stars == 0 and manager.economy.total_stars_earned == 12,
		"Victory banks the level's 12 stars once")
	_expect(_menu_contains("LEVEL 3 COMPLETE") and _menu_contains("You earned 12 stars!"), "Victory screen identifies the outcome and the stars")
	var rounds_ended := [0]
	manager.round_ended.connect(func() -> void: rounds_ended[0] += 1)
	_key(KEY_E)
	manager._process(1.0)
	_expect(rounds_ended[0] == 0 and manager.economy.stars == 12, "A finished level cannot end or pay twice")


func _check_hud() -> void:
	_start_level(3, 2)
	boat.global_position = people[0].global_position
	_key(KEY_E)
	boat.global_position = people[1].global_position
	_key(KEY_E)
	boat.global_position = harbor.global_position
	_key(KEY_E)
	main.call("_refresh_hud")
	var stats: Dictionary = main.get("_stat_labels")
	var seconds := ceili(manager.time_remaining)
	var expected := {"ABOARD": "0/2", "DELIVERED": "2/4", "LOST": "0",
		"STAR BANK": "6", "TIME": "%d:%02d" % [floori(seconds / 60.0), seconds % 60]}
	for caption in expected:
		_expect(stats.has(caption) and stats[caption].text == expected[caption], "HUD %s shows %s" % [caption, expected[caption]])
	_expect(stats.size() == expected.size(), "The top HUD keeps exactly TIME, ABOARD, DELIVERED, LOST and STAR BANK as numeric readouts")
	var level_label := main.get("_round_label") as Label
	_expect(level_label != null and level_label.text == "LEVEL 3 / 5", "HUD identifies Level 3 of 5")
	var hearts: Array = main.get("_hearts")
	var in_water := 0
	for heart: SurvivorHeart in hearts:
		heart.advance(0.0)
		if heart.shown_state == Survivor.State.ACTIVE:
			in_water += 1
	_expect(hearts.size() == 4 and in_water == 2 and manager.active_count() == 2, "The heart row shows 4 hearts, 2 of them still in the water")


func _menu_contains(fragment: String) -> bool:
	var menu := main.get("_menu") as Control
	if menu == null:
		return false
	for label: Label in menu.find_children("*", "Label", true, false):
		if fragment.to_lower() in label.text.to_lower():
			return true
	return false


func _lose(person: Survivor) -> void:
	person.oxygen_remaining = 0.001
	person._process(0.01)


func _key(code: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = true
	root.push_input(event, true)
	event.pressed = false
	root.push_input(event, true)


func _physics_frames(count: int) -> void:
	for frame in range(count):
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
