extends SceneTree
## godot --headless --fixed-fps 60 --path . --script res://tests/intro_suite.gd
## Covers the 3-second level-start sequence that plays after Launch Rescue and after every
## Replay: the 3-2-1 countdown, the scripted white-boat arrival, the harbor-facing beam, the
## frozen game state, the hand-off to normal play, replay behaviour and frame-rate independence.
##
## Most sections drive the intro by hand: Main's own _process is switched off and the suite
## calls _advance_intro(dt) with the frame time it wants, which makes any frame rate
## reproducible. The "live" section runs the real engine loop instead.

const SEA_TOP := 116.0
const HULL_RADIUS := 12.0
const REQUIRED_CLEARANCE := 20.0 # Water between the hull and any obstacle along the whole path.
const RATES := [30.0, 60.0, 144.0]
## Dock pieces as drawn by harbor.gd, in world space (harbor is at 1038, 342).
const DOCK_PARTS := [Rect2(1081, 297, 69, 14), Rect2(1081, 373, 69, 14), Rect2(1096, 284, 55, 116)]

var checks: int = 0
var failures: Array[String] = []
var main: Node
var manager: RescueGameManager
var boat: RescueBoat
var emergency: EmergencyBoat
var lighthouse: Lighthouse
var harbor: Harbor
var people: Array[Survivor] = []
var round_starts: int = 0
var emergency_home := Vector2.ZERO


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("Display: %s" % DisplayServer.get_name())
	await _boot(true)
	if main == null:
		_finish()
		return
	await _check_launch_begins_intro()
	await _check_countdown_numbers()
	await _boot(true)
	await _check_boat_arrival()
	await _boot(true)
	await _check_path_clearance()
	await _boot(true)
	await _check_beam_toward_harbor()
	await _boot(true)
	await _check_state_frozen_until_finish()
	await _boot(true)
	await _check_activation_after_countdown()
	await _boot(true)
	await _check_frame_rate_independence()
	await _boot(false)
	await _check_live_input_is_ignored()
	await _boot(true)
	await _check_replay()
	await _boot(true)
	await _check_tutorial_not_modified()
	_finish()


# --- scene helpers --------------------------------------------------------------------------

## Fresh Main scene. With manual=true its _process is off so the suite owns the intro clock.
func _boot(manual: bool) -> void:
	if is_instance_valid(main):
		main.queue_free()
		await process_frame
	main = null
	var scene := load("res://scenes/main.tscn") as PackedScene
	_expect(scene != null, "Main scene loads")
	if scene == null:
		return
	main = scene.instantiate()
	root.add_child(main)
	await process_frame
	manager = main.get("manager") as RescueGameManager
	boat = main.get("boat") as RescueBoat
	emergency = main.get("emergency") as EmergencyBoat
	lighthouse = main.get("lighthouse") as Lighthouse
	harbor = main.get("harbor") as Harbor
	if not manager or not boat or not emergency or not lighthouse or not harbor:
		_expect(false, "Main scene resolves both boats, manager, lighthouse and harbor")
		main = null
		return
	people.assign(manager.survivors)
	round_starts = 0
	manager.round_started.connect(func() -> void: round_starts += 1)
	emergency_home = emergency.global_position
	if manual:
		main.set_process(false)


## Plays the tutorial through its real buttons' handlers and launches.
func _launch_from_tutorial() -> void:
	for step in range(3):
		main.call("_tutorial_next")
	main.call("_launch_first_round")


## One simulated frame: Main first (as in the engine), then the nodes the intro must keep idle.
func _step(dt: float) -> void:
	main.call("_advance_intro", dt)
	manager._process(dt)
	lighthouse._process(dt)
	boat._physics_process(dt)


func _elapsed() -> float:
	return float(main.get("_intro_elapsed"))


func _intro_active() -> bool:
	return main.get("_intro_active") == true


func _number_label() -> Label:
	return (main.get("_countdown") as Control).find_child("CountdownNumber", true, false) as Label


func _caption_label() -> Label:
	return (main.get("_countdown") as Control).find_child("CountdownCaption", true, false) as Label


func _harbor_angle() -> float:
	return (harbor.global_position - lighthouse.global_position).angle()


func _angle_gap(a: float, b: float) -> float:
	return absf(wrapf(a - b, -PI, PI))


func _hud_clock() -> String:
	main.call("_refresh_hud")
	return ((main.get("_stat_labels") as Dictionary)["TIME"] as Label).text


func _rect_distance(point: Vector2, rect: Rect2) -> float:
	var nearest := Vector2(clampf(point.x, rect.position.x, rect.end.x), clampf(point.y, rect.position.y, rect.end.y))
	return point.distance_to(nearest)


## Runs the whole intro at one fixed frame time and records what each frame looked like.
func _run_intro_at(dt: float) -> Dictionary:
	var texts: Array[String] = []
	var ys: Array[float] = []
	var positions: Array[Vector2] = []
	var total := 0.0
	var guard := 0
	while _intro_active() and guard < 10000:
		texts.append(_number_label().text)
		ys.append(boat.global_position.y)
		positions.append(boat.global_position)
		_step(dt)
		total += dt
		guard += 1
	return {"texts": texts, "ys": ys, "positions": positions, "total": total, "frames": guard}


# --- sections -------------------------------------------------------------------------------

func _check_launch_begins_intro() -> void:
	_expect(main.get("_tutorial_open") == true and not _intro_active() and not (main.get("_countdown") as Control).visible,
		"Before launch the tutorial is open and no countdown is showing")
	for step in range(3):
		main.call("_tutorial_next")
	_expect(not _intro_active(), "Tutorial Next/Back steps never start the countdown")
	main.call("_launch_first_round")
	_expect(_intro_active() and (main.get("_countdown") as Control).visible,
		"Launch Rescue on the final step starts the countdown immediately")
	_expect(main.get("_tutorial_open") == false and main.get("_menu") == null, "The tutorial is gone while the countdown plays")
	_expect(not manager.round_active and round_starts == 0, "Launching does not start gameplay yet")
	main.call("_launch_first_round")
	_expect(is_zero_approx(_elapsed()) and round_starts == 0, "A second launch call is ignored")


func _check_countdown_numbers() -> void:
	var number := _number_label()
	var countdown := main.get("_countdown") as Control
	_expect(number != null and number.text == "3" and countdown.visible, "The countdown opens on 3")
	_expect(_caption_label().visible and "RESCUE BEGINS IN" in _caption_label().text, "A caption explains the countdown")
	_expect(countdown.mouse_filter == Control.MOUSE_FILTER_IGNORE and countdown.get_child_count() == 2,
		"The countdown is two labels with no backdrop, so it never blocks the world or the mouse")
	var number_rect := Rect2(number.position, number.size) # Unscaled box; the pop-in scale is cosmetic.
	_expect(absf(number_rect.get_center().x - 576.0) < 2.0 and number_rect.get_center().y > SEA_TOP + 60.0 and number_rect.get_center().y < 342.0
		and number.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER and number.vertical_alignment == VERTICAL_ALIGNMENT_CENTER,
		"The number is centred horizontally on the screen and sits over the middle of the sea area, clear of the lighthouse")
	_expect(number.get_theme_font_size("font_size") >= 120, "The number is large (at least 120 px)")
	var world := main.get_node("World") as CanvasItem
	_expect(world.visible and (main as CanvasItem).visible and boat.visible and lighthouse.visible and emergency.visible,
		"The gameplay world (lighthouse, boats, rocks) stays visible under the countdown")
	var shown: Array[String] = []
	var seconds_each := {}
	var dt := 1.0 / 60.0
	while _intro_active():
		var text := number.text
		if shown.is_empty() or shown[-1] != text:
			shown.append(text)
		seconds_each[text] = float(seconds_each.get(text, 0.0)) + dt
		_step(dt)
	_expect(shown == ["3", "2", "1"], "Numbers appear in the order 3, 2, 1 (saw %s)" % str(shown))
	var even := true
	for text in ["3", "2", "1"]:
		even = even and absf(float(seconds_each.get(text, 0.0)) - 1.0) <= 2.0 * dt
	_expect(even, "Each number is on screen for about one second (%s)" % str(seconds_each))
	_expect(is_equal_approx(_elapsed(), 3.0), "The countdown lasts exactly 3 seconds of game time")
	_expect(number.text == "GO!" and number.is_visible_in_tree(), "A brief GO! follows the 1")
	var go_frames := 0
	while float(main.get("_go_remaining")) > 0.0 and go_frames < 600:
		_step(dt)
		go_frames += 1
	_expect(go_frames * dt <= 1.0 and not number.is_visible_in_tree() and not _caption_label().is_visible_in_tree(),
		"GO! is brief (%.2f s) and then the overlay is hidden" % (go_frames * dt))
	_expect(manager.round_active, "Gameplay was already running while GO! was fading (it never delays play)")


func _check_boat_arrival() -> void:
	var spawn := manager.boat_spawn
	_launch_from_tutorial()
	var early := boat.global_position
	_expect(early.y < SEA_TOP - 20.0, "At t=0 the white boat is above the top edge of the visible sea (y=%.0f < %.0f)" % [early.y, SEA_TOP])
	_expect(early.x > 900.0 and absf(early.x - spawn.x) < 120.0, "It starts over the harbor side of the sea, on the right (x=%.0f)" % early.x)
	var dt := 1.0 / 60.0
	var previous := boat.global_position
	var entered_at := -1.0
	var max_step := 0.0
	var max_bend := 0.0
	var previous_step := Vector2.ZERO
	var monotonic := true
	var worst_heading_gap := 0.0
	var frames := 0
	var last_scripted := boat.global_position
	var last_scripted_heading := boat.heading
	while _intro_active():
		_step(dt)
		frames += 1
		if not _intro_active():
			break
		last_scripted = boat.global_position
		last_scripted_heading = boat.heading
		var here := boat.global_position
		var step_vector := here - previous
		if entered_at < 0.0 and here.y >= SEA_TOP + HULL_RADIUS:
			entered_at = _elapsed()
		monotonic = monotonic and step_vector.y >= -0.001
		max_step = maxf(max_step, step_vector.length())
		if previous_step != Vector2.ZERO and step_vector != Vector2.ZERO:
			max_bend = maxf(max_bend, _angle_gap(step_vector.angle(), previous_step.angle()))
			# Boat faces its direction of movement while it is really moving (it only swings round to
			# the berth heading in the last moments, once it has nearly stopped).
			if step_vector.length() >= 1.2:
				worst_heading_gap = maxf(worst_heading_gap, _angle_gap(boat.heading, step_vector.angle()))
		previous = here
		previous_step = step_vector
	_expect(entered_at > 0.0 and entered_at < 1.0, "It enters the visible scene within the first second (at %.2f s)" % entered_at)
	_expect(monotonic, "The boat only ever moves downward")
	_expect(max_step < 10.0 and max_step > 0.5, "No jumps: biggest per-frame move is %.2f px" % max_step)
	_expect(max_bend < 0.12, "The path bends smoothly (largest per-frame turn %.3f rad)" % max_bend)
	_expect(worst_heading_gap < 0.5, "The boat faces its direction of movement along the way (worst %.2f rad while moving at 72+ px/s)" % worst_heading_gap)
	_expect(main.call("_arrival_position", 1.0) == spawn, "The animated path itself ends exactly on the spawn point")
	_expect(last_scripted.distance_to(spawn) < 1.5 and _angle_gap(last_scripted_heading, PI) < 0.15,
		"Hand-off is seamless: one frame before activation the boat is already within %.2f px of the spawn and facing its start heading" % last_scripted.distance_to(spawn))
	_expect(boat.global_position == spawn, "At the end of the countdown the boat sits exactly on its spawn %s (got %s)" % [spawn, boat.global_position])
	_expect(is_equal_approx(boat.heading, PI) and boat.velocity == Vector2.ZERO, "It ends with its normal start heading and no residual speed")
	_expect(emergency.global_position == emergency_home, "The orange emergency boat never moved from its harbor spot")


func _check_path_clearance() -> void:
	_launch_from_tutorial()
	var rocks: Array[NavigationRock] = []
	for node in main.get_node("World/Rocks").get_children():
		if node is NavigationRock:
			rocks.append(node)
	_expect(rocks.size() >= 8, "The reef obstacles are found (%d)" % rocks.size())
	var lighthouse_radius := 55.0 # Island polygon extent plus its surf ring, as drawn.
	var worst := 1.0e9
	var worst_what := ""
	var inside_sea := true
	for index in range(0, 601):
		var progress := sin(float(index) / 600.0 * PI * 0.5)
		var point: Vector2 = main.call("_arrival_position", progress)
		if index > 0:
			inside_sea = inside_sea and point.x > 24.0 + HULL_RADIUS and point.x < 1128.0 - HULL_RADIUS
		for rock in rocks:
			var gap := point.distance_to(rock.global_position) - rock.radius - HULL_RADIUS
			if gap < worst:
				worst = gap
				worst_what = str(rock.name)
		var island_gap := point.distance_to(lighthouse.global_position) - lighthouse_radius - HULL_RADIUS
		if island_gap < worst:
			worst = island_gap
			worst_what = "lighthouse island"
		for part: Rect2 in DOCK_PARTS:
			var dock_gap := _rect_distance(point, part) - HULL_RADIUS
			if dock_gap < worst:
				worst = dock_gap
				worst_what = "dock"
	_expect(worst >= REQUIRED_CLEARANCE, "The whole path stays at least %.0f px clear of rocks, the lighthouse island and the dock (tightest: %.1f px near %s)" % [REQUIRED_CLEARANCE, worst, worst_what])
	_expect(inside_sea, "The path stays inside the playable sea")


func _check_beam_toward_harbor() -> void:
	# Pretend the beam was left pointing elsewhere (a previous round, or the mouse).
	lighthouse.beam_angle = -2.0
	_launch_from_tutorial()
	var expected := _harbor_angle()
	_expect(_angle_gap(lighthouse.beam_angle, expected) < 0.0001, "The beam is snapped to the harbor bearing at the start (%.3f rad)" % expected)
	_expect(expected == (harbor.global_position - lighthouse.global_position).angle(), "The bearing is computed from lighthouse to harbor")
	var always := true
	var mouse_far := Vector2(80, 560)
	var motion := InputEventMouseMotion.new()
	motion.position = mouse_far
	motion.global_position = mouse_far
	root.push_input(motion)
	var mouse_bearing := (lighthouse.get_global_mouse_position() - lighthouse.global_position).angle()
	_expect(_angle_gap(mouse_bearing, expected) > 0.5, "Test precondition: the mouse bearing differs from the harbor bearing")
	var dt := 1.0 / 60.0
	while _intro_active():
		_step(dt) # Includes lighthouse._process, which would follow the mouse if aiming were enabled.
		if not _intro_active():
			break
		lighthouse._process(0.5)
		always = always and _angle_gap(lighthouse.beam_angle, expected) < 0.0001 and not lighthouse.enabled
	_expect(always, "The beam stays on the harbor for the whole countdown, whatever the mouse does")
	_expect(lighthouse.enabled, "Mouse aiming is switched on when gameplay begins")
	lighthouse._process(1.0)
	_expect(_angle_gap(lighthouse.beam_angle, (lighthouse.get_global_mouse_position() - lighthouse.global_position).angle()) < 0.0001,
		"After the countdown the beam follows the mouse normally")


func _check_state_frozen_until_finish() -> void:
	_launch_from_tutorial()
	var stars := manager.stars
	var dt := 1.0 / 60.0
	var all_frozen := true
	var clock_text_ok := true
	var oxygen_full := true
	var dead_or_found := false
	var no_signals := true
	var emitted := []
	manager.round_ended.connect(func() -> void: emitted.append("round_ended"))
	manager.round_started.connect(func() -> void: emitted.append("round_started"))
	var frames := 0
	while _intro_active():
		_step(dt)
		frames += 1
		if not _intro_active():
			break
		all_frozen = all_frozen and not manager.round_active and not boat.controls_enabled and not lighthouse.enabled \
			and manager.result == RescueGameManager.Result.NONE and is_equal_approx(manager.time_remaining, 240.0) \
			and manager.stars == stars and manager.main_delivered == 0 and manager.emergency_delivered == 0 and manager.lost_count == 0 \
			and not emergency.is_physics_processing() and emergency.state == EmergencyBoat.State.READY
		clock_text_ok = clock_text_ok and _hud_clock() == "4:00"
		for person in people:
			oxygen_full = oxygen_full and is_equal_approx(person.oxygen_remaining, person.oxygen_duration)
			dead_or_found = dead_or_found or person.state != Survivor.State.ACTIVE or person.discovered
			oxygen_full = oxygen_full and not person.is_processing()
		no_signals = no_signals and emitted.is_empty()
	_expect(frames > 150, "The intro spans %d simulated frames" % frames)
	_expect(all_frozen, "For the whole countdown: round inactive, boat and lighthouse locked, emergency boat idle, nothing scored")
	_expect(clock_text_ok, "The HUD timer reads 4:00 for the whole countdown")
	_expect(oxygen_full, "All fifteen oxygen tanks stay full, and survivors are not processing")
	_expect(not dead_or_found, "No survivor dies, is rescued or is revealed during the countdown")
	_expect(no_signals, "No round_started or round_ended event (rescue, stars, victory, failure) fires before the end")


func _check_activation_after_countdown() -> void:
	_launch_from_tutorial()
	var dt := 1.0 / 60.0
	while _elapsed() < 2.95 and _intro_active():
		_step(dt)
	_expect(_intro_active() and not manager.round_active and not boat.controls_enabled and not lighthouse.enabled,
		"At 2.95 s everything is still locked")
	_expect(not is_equal_approx(boat.global_position.y, manager.boat_spawn.y) or boat.global_position != manager.boat_spawn,
		"…and the boat has not yet been snapped to the berth")
	var extra := 0
	while _intro_active() and extra < 10:
		_step(dt)
		extra += 1
	_expect(not _intro_active() and extra <= 4 and is_equal_approx(_elapsed(), 3.0), "The intro ends at 3 s (%d more frames after 2.95 s)" % extra)
	_expect(boat.global_position == manager.boat_spawn and boat.velocity == Vector2.ZERO,
		"Exactly at the end the boat is on its spawn")
	_expect(manager.round_active and boat.controls_enabled and lighthouse.enabled and emergency.is_physics_processing() and round_starts == 1,
		"Boat controls, mouse aiming, emergency dispatch and the round all activate together, once")
	_expect(manager.time_remaining > 239.9 and manager.time_remaining <= 240.0, "The 4:00 clock starts only now")
	var survivor_processing := true
	for person in people:
		survivor_processing = survivor_processing and person.is_processing()
	_expect(survivor_processing, "Oxygen starts draining only now (survivors process)")
	# Activation causes no teleport afterwards and normal control works.
	var before := boat.global_position
	Input.action_press("move_left")
	for i in range(20):
		boat._physics_process(dt)
	Input.action_release("move_left")
	_expect(boat.global_position.x < before.x - 1.0 or boat.velocity.x < -1.0, "The boat now responds to the steering keys")
	_expect(is_equal_approx(boat.base_speed, 100.0) and is_equal_approx(boat.acceleration, 300.0) and is_equal_approx(boat.deceleration, 240.0)
		and is_equal_approx(boat.turn_speed, 10.0) and is_equal_approx(boat.speed_multiplier, 1.0),
		"Speed, acceleration, deceleration and turn rate are the normal values")
	_expect(boat.collision_layer == 2 and boat.collision_mask == 1, "Collision layers are unchanged")
	# Emergency dispatch works after the countdown.
	var target := people[0]
	target.discovered = true
	_expect(manager.dispatch_at(target.global_position) or emergency.state != EmergencyBoat.State.READY,
		"The emergency boat can be dispatched after the countdown")


func _check_frame_rate_independence() -> void:
	var reference_positions := {}
	for rate in RATES:
		_launch_from_tutorial_again()
		var dt: float = 1.0 / float(rate)
		var data := _run_intro_at(dt)
		var texts: Array[String] = data["texts"]
		var order: Array[String] = []
		for text in texts:
			if order.is_empty() or order[-1] != text:
				order.append(text)
		var total := float(data["total"])
		_expect(order == ["3", "2", "1"], "%d fps: the countdown reads 3, 2, 1" % int(rate))
		_expect(absf(total - 3.0) <= dt + 0.0001, "%d fps: it ends after 3.00 s of game time (%.3f s)" % [int(rate), total])
		_expect(boat.global_position == manager.boat_spawn and manager.round_active, "%d fps: the boat lands on the spawn as gameplay starts" % int(rate))
		var ys: Array[float] = data["ys"]
		_expect(ys[0] < SEA_TOP - 20.0, "%d fps: the first frame has the boat above the sea" % int(rate))
		# Position at t = 1.5 s must be the same regardless of the frame rate.
		var index := int(round(1.5 / dt))
		reference_positions[rate] = (data["positions"] as Array[Vector2])[index]
	var a: Vector2 = reference_positions[30.0]
	var b: Vector2 = reference_positions[60.0]
	var c: Vector2 = reference_positions[144.0]
	_expect(a.distance_to(b) < 1.0 and b.distance_to(c) < 1.0, "The boat is at the same place at t=1.5 s at 30, 60 and 144 fps (%s %s %s)" % [a, b, c])
	# An uneven, stuttering frame time still totals 3 s and still lands exactly.
	_launch_from_tutorial_again()
	var starts_before := round_starts
	var jitter := [0.004, 0.05, 0.016, 0.1, 0.008, 0.033, 0.02]
	var total := 0.0
	var turn := 0
	var ended := false
	while _intro_active() and turn < 5000:
		var dt: float = jitter[turn % jitter.size()]
		_step(dt)
		total += dt
		turn += 1
	ended = not _intro_active()
	_expect(ended and total < 3.0 + 0.11 and boat.global_position == manager.boat_spawn and manager.round_active and round_starts == starts_before + 1,
		"Uneven frame times (4-100 ms) still end at 3 s on the spawn with one activation")
	# One enormous hitch (a 5 s frame) must not skip the activation hand-off.
	_launch_from_tutorial_again()
	starts_before = round_starts
	_step(5.0)
	_expect(not _intro_active() and boat.global_position == manager.boat_spawn and manager.round_active and round_starts == starts_before + 1,
		"A single 5 s hitch completes the intro cleanly")


## Launches again on the already-booted scene (via Replay, the same path a player uses).
func _launch_from_tutorial_again() -> void:
	if main.get("_tutorial_open") == true:
		_launch_from_tutorial()
		return
	# Finish any round in progress, then Replay.
	manager.round_active = false
	main.call("_retry_round")


func _check_live_input_is_ignored() -> void:
	# Real engine loop: Main._process drives the intro.
	_launch_from_tutorial()
	var start_y := boat.global_position.y
	_expect(start_y < SEA_TOP - 20.0, "(live) the boat starts above the visible sea")
	Input.action_press("move_left")
	Input.action_press("move_down")
	var target := people[9]
	var click_world := target.global_position
	var ok_positions := true
	var ok_locks := true
	var ok_oxygen := true
	var ok_quiet := true
	var frames := 0
	while _intro_active() and frames < 1500:
		await process_frame
		frames += 1
		if frames == 20:
			_key(KEY_E)
			_key(KEY_ESCAPE)
			_right_click(click_world)
		if not _intro_active():
			break
		var progress := sin(_elapsed() / 3.0 * PI * 0.5)
		var path_point: Vector2 = main.call("_arrival_position", progress)
		ok_positions = ok_positions and boat.global_position.distance_to(path_point) < 1.5
		ok_locks = ok_locks and not manager.round_active and not boat.controls_enabled and not lighthouse.enabled
		ok_quiet = ok_quiet and emergency.state == EmergencyBoat.State.READY and emergency.target == null \
			and emergency.global_position == emergency_home and main.get("_paused") == false and not get_root().get_tree().paused
		for person in people:
			ok_oxygen = ok_oxygen and is_equal_approx(person.oxygen_remaining, person.oxygen_duration) and person.state == Survivor.State.ACTIVE
		ok_oxygen = ok_oxygen and boat.passengers.is_empty() and is_equal_approx(manager.time_remaining, 240.0)
	Input.action_release("move_left")
	Input.action_release("move_down")
	_expect(frames > 100, "(live) the real frame loop ran the intro for %d frames" % frames)
	_expect(ok_positions, "(live) held steering keys never move the boat off its scripted path")
	_expect(ok_locks, "(live) round, boat controls and lighthouse stay locked during the countdown")
	_expect(ok_quiet, "(live) E, Esc and a right-click on a survivor do nothing: no pickup, no pause, no dispatch")
	_expect(ok_oxygen, "(live) timer and oxygen stay frozen, nobody is picked up")
	await process_frame
	_expect(manager.round_active and boat.global_position.distance_to(manager.boat_spawn) < 2.0 and boat.controls_enabled and lighthouse.enabled,
		"(live) gameplay starts when the countdown ends, with the boat on its spawn")
	# And the controls are real afterwards.
	var x0 := boat.global_position.x
	Input.action_press("move_left")
	for i in range(30):
		await physics_frame
	Input.action_release("move_left")
	_expect(boat.global_position.x < x0 - 3.0, "(live) steering works once gameplay has begun")
	_expect(manager.time_remaining < 240.0, "(live) the clock runs once gameplay has begun")
	_key(KEY_ESCAPE)
	_expect(main.get("_paused") == true, "(live) Esc pauses once gameplay has begun")
	_key(KEY_ESCAPE)


func _check_replay() -> void:
	_launch_from_tutorial()
	var dt := 1.0 / 60.0
	while _intro_active():
		_step(dt)
	# Earn stars with four real trips (2 survivors each), buy the upgrade, then run out the clock.
	for pair in [[0, 1], [2, 3], [4, 5], [6, 7]]:
		for index in pair:
			boat.global_position = people[index].global_position
			manager.try_interact()
		boat.global_position = harbor.global_position
		manager.try_interact()
	_expect(manager.stars == 24 and manager.main_delivered == 8, "(setup) eight main-boat deliveries banked 24 stars")
	lighthouse.beam_angle = 2.5
	manager._process(manager.time_remaining)
	_expect(not manager.round_active and main.get("_menu") != null, "(setup) the round ended and the results screen is open")
	var bought := manager.buy_speed_upgrade()
	var bank := manager.stars
	_expect(bank > 0, "(setup) some unspent stars remain after the purchase (%d)" % bank)
	_expect(bought and boat.speed_multiplier > 1.0, "(setup) a speed upgrade is purchased")
	var upgraded_speed := boat.speed_multiplier
	for round_number in range(1, 4):
		var replay: Button = null
		for button: Button in (main.get("_menu") as Control).find_children("*", "Button", true, false):
			if button.text == "REPLAY LEVEL 1":
				replay = button
		_expect(replay != null, "Replay #%d: the results screen offers Replay Level 1" % round_number)
		if replay == null:
			return
		var starts := round_starts
		replay.pressed.emit()
		_expect(_intro_active() and not manager.round_active and round_starts == starts, "Replay #%d: the countdown repeats before play" % round_number)
		_expect(main.get("_tutorial_open") == false and main.get("_menu") == null and _node_in_tree("TutorialTitle") == false,
			"Replay #%d: the tutorial does not reopen" % round_number)
		_expect(boat.global_position.y < SEA_TOP - 20.0 and (main.get("_countdown") as Control).visible and _number_label().text == "3",
			"Replay #%d: the boat is back above the sea and the countdown restarts at 3" % round_number)
		_expect(_angle_gap(lighthouse.beam_angle, _harbor_angle()) < 0.0001, "Replay #%d: the beam is reset toward the harbor" % round_number)
		_expect(is_equal_approx(manager.time_remaining, 240.0) and manager.main_delivered == 0 and manager.lost_count == 0
			and manager.result == RescueGameManager.Result.NONE and boat.passengers.is_empty() and emergency.global_position == emergency_home,
			"Replay #%d: round state is reset as before (4:00, no deliveries, boats home)" % round_number)
		_expect(manager.stars == bank and is_equal_approx(boat.speed_multiplier, upgraded_speed), "Replay #%d: the star bank and the upgrade persist" % round_number)
		var oxygen_full := true
		for person in people:
			oxygen_full = oxygen_full and is_equal_approx(person.oxygen_remaining, person.oxygen_duration) and person.state == Survivor.State.ACTIVE
		_expect(oxygen_full, "Replay #%d: all fifteen survivors are fresh" % round_number)
		while _intro_active():
			_step(dt)
		_expect(manager.round_active and round_starts == starts + 1 and boat.global_position == manager.boat_spawn and manager.stars == bank,
			"Replay #%d: gameplay begins once, with the boat on its spawn and no stars lost" % round_number)
		if round_number < 3:
			lighthouse.beam_angle = -1.0
			manager._process(manager.time_remaining)
			_expect(main.get("_menu") != null, "(setup) round %d ended; results are showing" % round_number)


func _check_tutorial_not_modified() -> void:
	## The countdown must leave the tutorial exactly as it was: content, navigation, start state.
	_expect(main.get("_tutorial_open") == true and main.get("_tutorial_step") == 0 and not _intro_active() and not manager.round_active,
		"At startup the tutorial (step 1) is shown, with no countdown and no round")
	_expect(_find_button("TutorialBack") == null and _find_button("TutorialNext") != null, "Step 1: Back is absent, Next is offered")
	for step in range(1, 4):
		main.call("_tutorial_next")
		_expect(main.get("_tutorial_step") == step and not _intro_active(), "Next moves to step %d without any countdown" % (step + 1))
	var launch := _find_button("TutorialLaunch")
	_expect(launch != null and launch.text == "Launch Rescue" and _find_button("TutorialNext") == null, "Only step 4 offers Launch Rescue")
	main.call("_tutorial_back")
	_expect(main.get("_tutorial_step") == 2 and _find_button("TutorialLaunch") == null and _find_button("TutorialNext") != null,
		"Back returns to step 3, where Launch Rescue is gone again")
	main.call("_tutorial_next")
	_expect(not manager.round_active and not _intro_active(), "No countdown or gameplay while the tutorial is still open")


# --- small utilities ------------------------------------------------------------------------

func _find_button(node_name: String) -> Button:
	var menu := main.get("_menu") as Control
	return null if menu == null else menu.find_child(node_name, true, false) as Button


func _node_in_tree(node_name: String) -> bool:
	var menu := main.get("_menu") as Control
	return menu != null and menu.find_child(node_name, true, false) != null


func _key(code: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = true
	root.push_input(event, true)
	event.pressed = false
	root.push_input(event, true)


func _right_click(world_point: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_RIGHT
	event.position = main.get_canvas_transform() * world_point
	event.pressed = true
	root.push_input(event, true)
	event.pressed = false
	root.push_input(event, true)


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
	Input.action_release("move_up")
	Input.action_release("move_down")
	print("INTRO SUITE: %d/%d checks passed" % [checks - failures.size(), checks])
	if is_instance_valid(main):
		main.queue_free()
	quit(0 if failures.is_empty() else 1)
