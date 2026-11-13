extends SceneTree
## godot --headless --fixed-fps 60 --path . --script res://tests/runtime_suite.gd
## Transition fixtures move the player between contacts; the emergency boat sails both legs.

var checks: int = 0
var failures: Array[String] = []
var main: Node
var manager: RescueGameManager
var boat: RescueBoat
var emergency: EmergencyBoat
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
	emergency = main.get("emergency") as EmergencyBoat
	lighthouse = main.get("lighthouse") as Lighthouse
	harbor = main.get("harbor") as Harbor
	_expect(manager != null and boat != null and emergency != null and lighthouse != null and harbor != null,
		"Main scene resolves both boats, manager, lighthouse and harbor")
	if not manager or not boat or not emergency or not lighthouse or not harbor:
		_finish()
		return
	people.assign(manager.survivors)
	_expect(people.size() == 15, "Level contains fifteen survivors")
	if people.size() != 15:
		_finish()
		return
	await _check_level()
	await _check_movement()
	_check_discovery()
	_check_main_rescue()
	await _check_emergency_trip()
	await _check_unavailable_target()
	await _check_failures_and_retry()
	await _check_victory_and_shop()
	_finish()


func _check_level() -> void:
	_expect(ProjectSettings.get_setting("application/run/main_scene") == "res://scenes/main.tscn",
		"Project main scene is configured")
	_expect(ProjectSettings.get_setting("rendering/renderer/rendering_method") == "gl_compatibility",
		"Compatibility renderer is configured")
	var durations := {}
	var ids := {}
	var positions := {}
	for person in people:
		ids[person.survivor_id] = true
		durations[person.oxygen_duration] = true
		positions[person.global_position] = true
	_expect(ids.size() == 15 and positions.size() == 15, "Every survivor has a unique ID and position")
	_expect(durations.size() == 15, "Every survivor has an individual oxygen budget")
	_expect(not manager.round_active and not boat.controls_enabled and not lighthouse.enabled,
		"Briefing freezes gameplay")
	var initial_oxygen := people[0].oxygen_remaining
	await _physics_frames(4)
	_expect(is_equal_approx(initial_oxygen, people[0].oxygen_remaining), "Oxygen waits for launch")
	manager.start_round()
	_expect(manager.round_active and boat.controls_enabled and lighthouse.enabled, "Launch activates the round")
	_expect(boat.capacity == 2 and boat.passengers.is_empty(), "Main boat begins with two empty seats")
	_expect(emergency.capacity == 1 and emergency.passengers.is_empty() and emergency.state == EmergencyBoat.State.READY,
		"Emergency boat starts ready with one empty seat")
	_expect(emergency.speed < boat.base_speed, "Emergency boat is slower than the main boat")
	_expect(harbor.contains_point(boat.global_position) and harbor.contains_point(emergency.global_position),
		"Both boats start at the safe harbor")
	_expect(is_equal_approx(manager.level_duration, 240.0) and is_equal_approx(manager.time_remaining, 240.0),
		"Level 1 has a four-minute deadline")
	_expect(not manager.buy_speed_upgrade(), "Upgrades cannot be bought during a round")


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

	var person := people[6]
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
	manager.restart_round()


func _check_main_rescue() -> void:
	var person := people[0]
	var initial_oxygen := person.oxygen_remaining
	person._process(1.0)
	_expect(is_equal_approx(person.oxygen_remaining, initial_oxygen - 1.0), "Oxygen decreases in the water")
	boat.global_position = person.global_position
	_expect(not person.discovered and not person.visible, "Contact begins unseen even at the pickup location")
	_key(KEY_E)
	_expect(person.state == Survivor.State.ON_MAIN_BOAT and boat.passengers.has(person),
		"E boards a nearby survivor before any lighthouse or proximity detection tick")
	initial_oxygen = person.oxygen_remaining
	person._process(20.0)
	_expect(is_equal_approx(initial_oxygen, person.oxygen_remaining), "Oxygen stops on the main boat")
	var second := people[1]
	boat.global_position = second.global_position + Vector2(0, boat.pickup_radius * 0.8)
	lighthouse.aim_at(2.0 * lighthouse.global_position - second.global_position, 2.0)
	manager._process(0.0)
	_expect(second.visible and not lighthouse.is_illuminated(second.global_position), "Proximity makes an unlit contact visible")
	_key(KEY_E)
	_expect(second.state == Survivor.State.ON_MAIN_BOAT and boat.passengers.size() == 2, "E fills the second seat")
	_expect(manager.rescued_count == 0 and manager.stars == 0, "Pickup alone gives no successful rescue or currency")
	boat.global_position = people[2].global_position
	_key(KEY_E)
	_expect(boat.passengers.size() == 2 and people[2].state == Survivor.State.ACTIVE, "Capacity prevents a third passenger")
	_expect("FULL" in manager.context_hint().to_upper(), "Full boat gets a return instruction")
	boat.global_position = harbor.global_position
	_key(KEY_E)
	_expect(boat.passengers.is_empty() and manager.main_delivered == 2 and manager.rescued_count == 2,
		"Harbor E unloads both seats and credits both main-boat rescues")
	_expect(person.state == Survivor.State.DELIVERED and second.state == Survivor.State.DELIVERED, "Unloaded survivors are delivered")
	_expect(manager.stars == 6 and manager.stars_per_survivor == 3, "Each main-boat delivery earns three stars")
	_key(KEY_E)
	_expect(manager.rescued_count == 2 and manager.stars == 6, "Empty unload cannot duplicate rewards")


func _check_emergency_trip() -> void:
	var person := people[6] # Far-west contact; direct travel from the dock intersects the island.
	var origin := emergency.global_position
	var island_shape := lighthouse.get_node("IslandBody/CollisionShape2D") as CollisionShape2D
	var island_radius := (island_shape.shape as CircleShape2D).radius
	var hull_shape := emergency.get_node("CollisionShape2D") as CollisionShape2D
	var hull_radius := (hull_shape.shape as CircleShape2D).radius
	_expect(Geometry2D.get_closest_point_to_segment(island_shape.global_position, origin, person.global_position).distance_to(island_shape.global_position) < island_radius + hull_radius,
		"Emergency route fixture crosses the island on a straight bearing")
	_expect(not manager.dispatch_at(person.global_position), "An unseen target cannot be assigned")
	_illuminate(person)
	_right_click(person)
	_expect(emergency.state == EmergencyBoat.State.TRAVELING and emergency.target == person, "Right-click dispatches the ready boat to a visible survivor")
	_expect(not manager.dispatch_at(person.global_position), "Duplicate dispatch is rejected")
	await _physics_frames(10)
	_expect(emergency.global_position.distance_to(origin) > 0.0, "Emergency boat advances under its own power")
	await _check_pause(person)
	lighthouse.aim_at(2.0 * lighthouse.global_position - person.global_position, 2.0)
	manager._process(person.visibility_memory_duration + 0.1)
	_expect(not person.visible and emergency.target == person, "The assignment survives the target fading from view")
	var initial_stars := manager.stars
	var previous := emergency.global_position
	var clear := true
	var saw_rescuing := false
	var saw_return := false
	var hold_oxygen := 0.0
	var froze_oxygen := true
	for frame in range(3600):
		await physics_frame
		var current := emergency.global_position
		clear = clear and _hull_cleared_segment(previous, current, island_shape.global_position, island_radius + hull_radius)
		for rock: NavigationRock in main.get_node("World/Rocks").get_children():
			clear = clear and _hull_cleared_segment(previous, current, rock.global_position, rock.radius + hull_radius)
		previous = current
		if emergency.state == EmergencyBoat.State.RESCUING:
			saw_rescuing = true
		if person.state == Survivor.State.ON_EMERGENCY_BOAT:
			if not saw_return:
				hold_oxygen = person.oxygen_remaining
			saw_return = true
			froze_oxygen = froze_oxygen and is_equal_approx(person.oxygen_remaining, hold_oxygen)
		if emergency.state == EmergencyBoat.State.COOLDOWN:
			break
	_expect(clear, "Emergency hull clears every rock and the lighthouse island along both legs")
	_expect(saw_rescuing and saw_return, "Emergency boat reaches the target, rescues and carries it home")
	_expect(saw_return and froze_oxygen, "Emergency passenger oxygen freezes for the return trip")
	_expect(person.state == Survivor.State.DELIVERED and emergency.passengers.is_empty() and harbor.contains_point(emergency.global_position),
		"Emergency boat unloads automatically in the harbor")
	_expect(manager.emergency_delivered == 1 and manager.rescued_count == 3 and manager.lost_count == 0,
		"Emergency delivery increases rescued totals without recording a death")
	_expect(manager.stars == initial_stars, "Emergency delivery preserves the existing star bank exactly")
	_check_hud()
	_illuminate(people[3])
	_expect(emergency.state == EmergencyBoat.State.COOLDOWN and not manager.dispatch_at(people[3].global_position),
		"Dock cooldown blocks the next assignment")
	var remaining := emergency.cooldown_remaining
	_key(KEY_ESCAPE)
	await _physics_frames(8)
	_expect(is_equal_approx(remaining, emergency.cooldown_remaining), "Pause freezes emergency cooldown")
	_key(KEY_ESCAPE)
	await _physics_frames(ceili(emergency.cooldown_duration * Engine.physics_ticks_per_second) + 3)
	_expect(emergency.state == EmergencyBoat.State.READY, "Emergency boat becomes ready when cooldown expires")


func _check_pause(person: Survivor) -> void:
	_key(KEY_ESCAPE)
	_expect(paused, "Escape pauses the gameplay tree")
	var oxygen := person.oxygen_remaining
	var remaining := manager.time_remaining
	var angle := lighthouse.beam_angle
	var boat_position := boat.global_position
	var emergency_position := emergency.global_position
	Input.action_press("move_left")
	await _physics_frames(8)
	_expect(is_equal_approx(oxygen, person.oxygen_remaining) and is_equal_approx(remaining, manager.time_remaining),
		"Pause freezes oxygen and level time")
	_expect(is_equal_approx(angle, lighthouse.beam_angle) and boat.global_position.is_equal_approx(boat_position), "Pause freezes the lighthouse and player boat")
	_expect(emergency.global_position.is_equal_approx(emergency_position) and emergency.target == person, "Pause freezes the dispatched boat")
	Input.action_release("move_left")
	_key(KEY_ESCAPE)
	await _physics_frames(3)
	_expect(not paused and person.oxygen_remaining < oxygen and manager.time_remaining < remaining and emergency.global_position != emergency_position,
		"Escape resumes both clocks and the emergency mission")


func _hull_cleared_segment(start: Vector2, end: Vector2, obstacle: Vector2, clearance: float) -> bool:
	var nearest := start if start.is_equal_approx(end) else Geometry2D.get_closest_point_to_segment(obstacle, start, end)
	return nearest.distance_to(obstacle) >= clearance - 0.1


func _check_hud() -> void:
	main.call("_refresh_hud")
	var stats: Dictionary = main.get("_stat_labels")
	var seconds := ceili(manager.time_remaining)
	var expected := {"ABOARD": "0/2", "MAIN": "2", "EMERGENCY": "1", "DELIVERED": "3", "LOST": "0/3",
		"IN THE WATER": "12", "STAR BANK": "6", "TIME": "%d:%02d" % [floori(seconds / 60.0), seconds % 60]}
	for caption in expected:
		_expect(stats.has(caption) and stats[caption].text == expected[caption], "HUD %s shows %s" % [caption, expected[caption]])
	var level_label := main.get("_round_label") as Label
	_expect(level_label != null and "LEVEL 1" in level_label.text.to_upper(), "HUD identifies Level 1")
	var label := main.get("_emergency_label") as Label
	_expect(label != null and "COOLDOWN" in label.text and "0/1" in label.text, "Emergency HUD shows cooldown status and its passenger capacity")


func _check_unavailable_target() -> void:
	manager.restart_round()
	var person := people[6]
	_illuminate(person)
	_expect(manager.dispatch_at(person.global_position), "New task starts from ready")
	await _physics_frames(30)
	boat.global_position = person.global_position
	_key(KEY_E)
	_expect(person.state == Survivor.State.ON_MAIN_BOAT, "The player can rescue a contact while the emergency boat is en route")
	await _physics_frames(180)
	_expect(emergency.target == null and emergency.passengers.is_empty() and harbor.contains_point(emergency.global_position),
		"Emergency boat returns safely after its target boards the player boat")
	_expect(manager.rescued_count == 0 and manager.lost_count == 0,
		"A withdrawn target has no emergency delivery or loss")
	manager.restart_round()
	_illuminate(person)
	manager.dispatch_at(person.global_position)
	await _physics_frames(30)
	_lose(person)
	await _physics_frames(180)
	_expect(emergency.target == null and emergency.passengers.is_empty() and harbor.contains_point(emergency.global_position),
		"Emergency boat returns safely if its assigned survivor dies")


func _check_failures_and_retry() -> void:
	var person := people[6]
	_expect(person.state == Survivor.State.LOST and manager.lost_count == 1, "Oxygen exhaustion signals one loss")
	_expect(not person.pick_up() and not manager.dispatch_at(person.global_position), "Lost survivors reject pickup and dispatch")
	_lose(people[0])
	_expect(manager.round_active and manager.lost_count == 2, "Level continues at two deaths")
	_lose(people[1])
	_expect(not manager.round_active and manager.result == RescueGameManager.Result.TOO_MANY_LOST and manager.lost_count == 3,
		"The third death immediately triggers the loss threshold")
	_expect(_menu_contains("Too Many Survivors Lost"), "Loss screen explains the death threshold")
	_expect(not boat.controls_enabled and not lighthouse.enabled, "Game over disables steering and lighthouse control")
	var oxygen := people[2].oxygen_remaining
	var remaining := manager.time_remaining
	await _physics_frames(4)
	_expect(is_equal_approx(oxygen, people[2].oxygen_remaining) and is_equal_approx(remaining, manager.time_remaining),
		"Results freeze the unresolved contacts and the level clock")
	_expect(not manager.buy_speed_upgrade(), "A shop purchase requires sufficient stars")

	manager.restart_round()
	boat.global_position = people[0].global_position
	_key(KEY_E)
	_illuminate(people[6])
	manager.dispatch_at(people[6].global_position)
	manager._process(manager.time_remaining)
	_expect(not manager.round_active and manager.time_remaining == 0.0 and manager.result == RescueGameManager.Result.TIME_RAN_OUT,
		"Countdown expiry is a distinct failure even with a living passenger aboard")
	_expect(_menu_contains("Time Ran Out"), "Timeout screen explains the deadline")
	var stopped_position := emergency.global_position
	await _physics_frames(10)
	_expect(emergency.global_position == stopped_position, "Timeout freezes a dispatched emergency boat")
	var previous_stars := manager.stars
	manager.restart_round()
	_expect(manager.round_active and manager.round_index == 1 and manager.result == RescueGameManager.Result.NONE and manager.time_remaining == manager.level_duration,
		"Retry restores the Level 1 clock and clears the result")
	_expect(manager.main_delivered == 0 and manager.emergency_delivered == 0 and manager.lost_count == 0 and manager.stars == previous_stars,
		"Retry clears round statistics and keeps the earned bank")
	var clean := true
	for survivor in people:
		clean = clean and survivor.state == Survivor.State.ACTIVE and not survivor.discovered and not survivor.visible and is_equal_approx(survivor.oxygen_remaining, survivor.oxygen_duration)
	_expect(clean, "Retry resets all fifteen oxygen tanks, states and markers")
	_expect(boat.passengers.is_empty() and emergency.passengers.is_empty() and emergency.target == null and emergency.state == EmergencyBoat.State.READY and harbor.contains_point(emergency.global_position),
		"Retry clears manifests, dispatch, cooldown and emergency position")


func _check_victory_and_shop() -> void:
	# Two losses and 12 player deliveries leave one emergency passenger on the return leg.
	var target := people[6]
	_illuminate(target)
	manager.dispatch_at(target.global_position)
	_lose(people[13])
	_lose(people[14])
	for person in people:
		if person == target or person.state != Survivor.State.ACTIVE:
			continue
		boat.global_position = person.global_position
		_key(KEY_E)
		if boat.is_full():
			boat.global_position = harbor.global_position
			_key(KEY_E)
	_expect(manager.main_delivered == 12 and manager.round_active, "Twelve main deliveries and two losses leave the last rescue in play")
	for frame in range(3600):
		await physics_frame
		if target.state == Survivor.State.ON_EMERGENCY_BOAT:
			break
	_expect(target.state == Survivor.State.ON_EMERGENCY_BOAT and manager.active_count() == 0 and manager.round_active,
		"Victory waits for the last passenger on the emergency boat")
	for frame in range(3600):
		await physics_frame
		if not manager.round_active:
			break
	_expect(manager.result == RescueGameManager.Result.VICTORY and manager.rescued_count == 13 and manager.lost_count == 2,
		"Final harbor delivery wins with thirteen delivered and two lost")
	_expect(manager.emergency_delivered == 1 and manager.main_delivered == 12 and manager.time_remaining > 0.0,
		"Victory includes both fleets before the deadline")
	_expect(_menu_contains("LEVEL 1 COMPLETE"), "Victory screen identifies the successful outcome")

	var previous_stars := manager.stars
	var speed_price := manager.speed_cost()
	var shop_button := main.get("_speed_button") as Button
	_expect(not shop_button.disabled, "Earned stars unlock the results-screen speed purchase")
	shop_button.pressed.emit()
	_expect(manager.speed_level == 1 and _menu_contains("Upgrade purchased"), "The speed purchase applies and gives feedback in the shop")
	_expect(manager.stars == previous_stars - speed_price and manager.speed_cost() > speed_price,
		"A purchase charges exactly the price and raises the next price")
	previous_stars = manager.stars
	manager.restart_round()
	_expect(manager.round_index == 1 and manager.stars == previous_stars and boat.speed_multiplier > 1.0,
		"Level 1 replay retains the purchased upgrade and unspent stars")
	boat.global_position = Vector2(2000, 2000)
	Input.action_press("move_right")
	await _physics_frames(90)
	Input.action_release("move_right")
	_expect(boat.velocity.x > boat.base_speed and is_equal_approx(boat.velocity.x, boat.base_speed * boat.speed_multiplier),
		"Upgrade raises measured top speed under normal movement input")

	# With everyone alive, one remaining main passenger must also reach the dock.
	manager.restart_round()
	for person in people:
		boat.global_position = person.global_position
		_key(KEY_E)
		if boat.is_full():
			boat.global_position = harbor.global_position
			_key(KEY_E)
	_expect(manager.active_count() == 0 and boat.passengers.size() == 1 and manager.round_active,
		"Victory waits for the last passenger on the main boat")
	boat.global_position = harbor.global_position
	_key(KEY_E)
	_expect(manager.result == RescueGameManager.Result.VICTORY and manager.rescued_count == 15 and manager.lost_count == 0,
		"All fifteen delivered is also a victory")
	var bank_before := manager.stars
	var second_price := manager.speed_cost()
	_expect(manager.buy_speed_upgrade() and manager.stars == bank_before - second_price,
		"The second speed level charges its higher price")
	var final_price := manager.speed_cost()
	_expect(final_price > second_price and manager.buy_speed_upgrade(), "The third speed level has a higher price")
	manager.restart_round()
	for person in people:
		boat.global_position = person.global_position
		_key(KEY_E)
		boat.global_position = harbor.global_position
		_key(KEY_E)
	bank_before = manager.stars
	_expect(bank_before >= manager.speed_cost() and not manager.buy_speed_upgrade() and manager.stars == bank_before,
		"Maximum speed level blocks another purchase even with sufficient funds")


func _menu_contains(fragment: String) -> bool:
	var menu := main.get("_menu") as Control
	if menu == null:
		return false
	for label: Label in menu.find_children("*", "Label", true, false):
		if fragment.to_lower() in label.text.to_lower():
			return true
	return false


func _illuminate(person: Survivor) -> void:
	lighthouse.aim_at(person.global_position, 2.0)
	manager._process(0.0)


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


func _right_click(person: Survivor) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_RIGHT
	event.position = person.get_global_transform_with_canvas().origin
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
