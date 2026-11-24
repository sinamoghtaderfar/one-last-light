extends SceneTree
## godot --headless --fixed-fps 60 --path . --script res://tests/tutorial_suite.gd
## Covers the one-page pre-launch briefing: content, the single Launch Rescue button, layout fit,
## the frozen game state while it is open, input isolation, the one-time launch,
## and the hand-off to pause, results, upgrades and replay.

const VIEWPORT := Rect2(0, 0, 1152, 648)
## Independent copy of the required wording, so an accidental content edit is caught.
const SPEC := [
	{
		"title": "Your Mission",
		"lines": [
			"People are drowning. Rescue them with your boat.",
			"Steer with WASD or the arrow keys. Aim the lighthouse with your mouse.",
			"Press E to pick people up, and E at the harbor to drop them off.",
		],
	},
]

var checks: int = 0
var failures: Array[String] = []
var main: Node
var manager: RescueGameManager
var boat: RescueBoat
var lighthouse: Lighthouse
var harbor: Harbor
var people: Array[Survivor] = []
var round_starts: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("Button input: %s" % ("button signals (--headless has no GUI mouse routing)" if DisplayServer.get_name() == "headless" else "real mouse click events"))
	var scene := load("res://scenes/main.tscn") as PackedScene
	_expect(scene != null, "Main scene loads")
	if scene == null:
		_finish()
		return
	main = scene.instantiate()
	root.add_child(main)
	await process_frame
	_expect(_node("LevelGrid") != null and main.get("_tutorial_open") == false, "Game startup opens the level map (main menu)")
	_expect((_node("PlayButton_1") as Button) != null and not (_node("PlayButton_1") as Button).disabled and (_node("PlayButton_2") as Button).disabled,
		"Only Level 1 can be played at the start")
	(_node("PlayButton_1") as Button).pressed.emit()
	manager = main.get("manager") as RescueGameManager
	boat = main.get("boat") as RescueBoat
	lighthouse = main.get("lighthouse") as Lighthouse
	harbor = main.get("harbor") as Harbor
	if not manager or not boat or not lighthouse or not harbor:
		_expect(false, "Main scene resolves the boat, manager, lighthouse and harbor")
		_finish()
		return
	people.assign(manager.survivors)
	manager.round_started.connect(func() -> void: round_starts += 1)
	_check_tutorial_matches_game_rules()
	await _check_startup()
	await _check_single_page()
	await _check_input_isolation()
	await _check_launch()
	await _check_pause_results_upgrade_and_replay()
	_finish()


## The tutorial text is built from the live data; pin what it quotes to the real rules.
func _check_tutorial_matches_game_rules() -> void:
	var durations_ok := true
	for person in people:
		durations_ok = durations_ok and is_equal_approx(person.visibility_memory_duration, 3.0)
	_expect(manager.levels.size() == 5 and is_equal_approx(manager.level.time_limit, 240.0),
		"Tutorial numbers match the rules: 5 levels and a 4-minute timer")
	_expect(boat.capacity == 1 and durations_ok,
		"Tutorial numbers match the rules: 1 starting seat, 3 seconds of visibility memory")
	var all_text := ""
	for step: Dictionary in main.call("_tutorial_content"):
		all_text += step["title"] + " " + " ".join(step["lines"]) + " "
	for removed in ["Emergency", "emergency", "Right-click", "15 survivors", "up to 2 survivors"]:
		_expect(not (removed in all_text), "Tutorial text no longer mentions '%s'" % removed)


func _check_startup() -> void:
	_expect(main.get("_tutorial_open") == true and main.get("_tutorial_step") == 0, "Choosing Level 1 the first time opens the briefing")
	_expect(not manager.round_active and round_starts == 0, "No round has started at startup")
	await _expect_page(0)
	await _expect_frozen("Step 1")
	_expect(_node("TutorialBack") == null, "Back is unavailable on step 1")
	main.call("_tutorial_back")
	_expect(main.get("_tutorial_step") == 0, "Back cannot move before step 1")


func _check_single_page() -> void:
	_expect((main.call("_tutorial_content") as Array).size() == 1, "The briefing is a single page")
	main.call("_tutorial_next")
	_expect(main.get("_tutorial_step") == 0 and _node("TutorialNext") == null and _node("TutorialLaunch") != null,
		"Next has nowhere to go; the page stays on Launch Rescue")
	await _expect_page(0)
	await _expect_frozen("After a stray Next")


func _check_input_isolation() -> void:
	var person := people[0]
	var beam := lighthouse.beam_angle
	var spawn := boat.global_position
	_key(KEY_E)
	_key(KEY_ESCAPE)
	_right_click(person) # Right-click no longer does anything in the game.
	Input.action_press("move_right")
	Input.action_press("move_up")
	await _physics_frames(12)
	lighthouse._process(1.0)
	Input.action_release("move_right")
	Input.action_release("move_up")
	_expect(boat.global_position.is_equal_approx(spawn) and boat.velocity == Vector2.ZERO, "WASD cannot move the main boat behind the tutorial")
	_expect(is_equal_approx(lighthouse.beam_angle, beam), "The mouse cannot aim the lighthouse behind the tutorial")
	_expect(not paused and main.get("_tutorial_open") == true and main.get("_tutorial_step") == 0 and _node("TutorialLaunch") != null,
		"Esc neither pauses the game nor dismisses the tutorial")
	boat.global_position = person.global_position
	_key(KEY_E)
	manager.try_interact()
	_expect(boat.passengers.is_empty() and person.state == Survivor.State.ACTIVE and manager.delivered_count == 0,
		"E beside a survivor cannot rescue anyone before launch")
	_expect(not manager.has_method("dispatch_at"), "The manager has no emergency dispatch left to call")
	boat.global_position = spawn
	await _expect_frozen("After stray keyboard and mouse input")
	_expect(round_starts == 0, "Stray input never starts a round")


func _check_launch() -> void:
	var launch := _node("TutorialLaunch") as Button
	_expect(launch != null and launch.text == "Launch Rescue", "The briefing offers Launch Rescue")
	var starts := round_starts
	await _press(launch)
	launch.pressed.emit() # A stale second press must not start anything.
	main.call("_launch_first_round")
	_expect(main.get("_tutorial_open") == false and main.get("_menu") == null and _node("TutorialTitle") == null,
		"The tutorial closes when Launch Rescue is pressed")
	_expect(main.get("_intro_active") == true and not manager.round_active and round_starts == starts,
		"Launch Rescue opens the 3-second countdown first, with no round running yet")
	await _wait_for_intro()
	_expect(round_starts == starts + 1, "Launch Rescue starts Level 1 exactly once")
	_expect(manager.round_active and lighthouse.enabled and manager.level_number == 1 and people.size() == 2,
		"Launch activates Level 1 (two survivors) and the lighthouse")
	_expect(not boat.controls_enabled and not boat.visible and main.get("_awaiting_mouse") == true,
		"In Level 1 the boat waits out of sight for the player's first mouse move")
	_expect(manager.time_remaining > 239.9 and manager.time_remaining <= 240.0, "The round begins with the full four minutes (at most a frame consumed)")
	await _physics_frames(30)
	_expect(manager.time_remaining < 240.0 and people[0].oxygen_remaining < people[0].oxygen_duration,
		"Timer and oxygen run after launch")
	boat.global_position = people[0].global_position
	_key(KEY_E)
	_expect(boat.passengers.size() == 1 and people[0].state == Survivor.State.ON_BOAT, "E rescues normally after launch")


func _check_pause_results_upgrade_and_replay() -> void:
	_key(KEY_ESCAPE)
	_expect(paused and _menu_contains("OPERATIONS PAUSED"), "Esc pauses the launched round")
	var remaining := manager.time_remaining
	await _physics_frames(6)
	_expect(is_equal_approx(remaining, manager.time_remaining), "Pause freezes the clock")
	_key(KEY_ESCAPE)
	_expect(not paused and main.get("_menu") == null, "Esc resumes and clears the pause screen")
	await _physics_frames(3)
	_expect(manager.time_remaining < remaining, "The clock resumes after pause")

	# Finish Level 1: deliver both survivors. The level completes with its rating and points.
	boat.global_position = harbor.global_position
	_key(KEY_E)
	_expect(manager.delivered_count == 1 and manager.round_active, "One of two delivered: Level 1 goes on")
	boat.global_position = people[1].global_position
	_key(KEY_E)
	boat.global_position = harbor.global_position
	_key(KEY_E)
	_expect(manager.delivered_count == 2 and manager.result == RescueGameManager.Result.VICTORY and manager.level_stars == 3 and manager.points == 200,
		"Delivering both Level 1 survivors quickly wins the level with 3 stars and 200 Light Points")
	_expect(_menu_contains("LEVEL 1 COMPLETE") and _menu_contains("+200 Light Points"), "The results screen shows LEVEL 1 COMPLETE with the points earned")
	var shop := _node("ShopButton") as Button
	_expect(shop != null and not shop.disabled, "The results screen offers the SHOP")
	shop.pressed.emit()
	var seat := _node("BuyButton_capacity_1") as Button
	_expect(seat != null and seat.disabled and seat.text == "LOCKED", "After Level 1 the Extra Seat is still locked (it unlocks at Level 4)")
	(_node("ShopBack") as Button).pressed.emit()
	_expect(manager.economy.capacity == 1 and manager.points == 200, "Nothing was bought; the points are kept")

	var next: Button = _node("ContinueButton") as Button
	_expect(next != null and next.text == "CONTINUE TO LEVEL 2", "Back on the results screen, Continue goes to Level 2")
	var starts := round_starts
	next.pressed.emit()
	_expect(main.get("_intro_active") == true and not manager.round_active and round_starts == starts and manager.level_number == 2,
		"Continue prepares Level 2 and runs the countdown before activating it")
	await _wait_for_intro()
	_expect(manager.round_active and round_starts == starts + 1 and manager.level_number == 2 and manager.survivors.size() == 3,
		"Level 2 then starts with its three survivors")
	_expect(main.get("_tutorial_open") == false and main.get("_menu") == null and _node("TutorialTitle") == null,
		"Continuing does not reopen the tutorial")
	_expect(boat.capacity == 1 and manager.points == 200, "Level 2 starts with one seat and the banked points")
	# Fail Level 2 on the clock and replay it: the upgrade stays.
	manager.level.time_limit_enabled = true # (fixture) levels ship without a time limit; it is a quick way to fail here
	manager._process(manager.time_remaining)
	manager.level.time_limit_enabled = false
	_expect(not manager.round_active and manager.result == RescueGameManager.Result.TIME_RAN_OUT and _menu_contains("Time ran out"),
		"The failure screen appears when the timer expires")
	var replay := _node("ReplayButton") as Button
	_expect(replay != null and replay.text == "RETRY LEVEL 2", "The failure screen offers Retry Level 2")
	starts = round_starts
	replay.pressed.emit()
	_expect(main.get("_intro_active") == true and not manager.round_active and round_starts == starts and manager.level_number == 2,
		"Replay prepares Level 2 and runs the countdown before activating it")
	await _wait_for_intro()
	_expect(manager.round_active and round_starts == starts + 1 and manager.level_number == 2, "Replay then starts Level 2")
	_expect(manager.time_remaining > 239.9 and manager.time_remaining <= 240.0 and manager.points == 200,
		"Replay restores the clock and keeps the points")


## Asserts one tutorial page: content, progress, buttons, layout and character coverage.
func _expect_page(step: int) -> void:
	await process_frame
	await process_frame
	var spec: Dictionary = SPEC[step]
	var page := "Step %d" % (step + 1)
	var menu := main.get("_menu") as Control
	_expect(menu != null and main.get("_tutorial_open") == true and main.get("_tutorial_step") == step, "%s is the active page" % page)
	if menu == null:
		return
	_expect(_node("TutorialStepLabel") == null and _node("TutorialProgress") == null, "%s has no step counter or progress bar" % page)
	_expect((_node("TutorialTitle") as Label).text == spec["title"], "%s is titled '%s'" % [page, spec["title"]])
	var body := _node("TutorialBody") as Control
	var shown: Array = []
	for line: Label in body.get_children():
		shown.append(line.text)
	_expect(shown == spec["lines"], "%s shows the required text" % page)

	var buttons := menu.find_children("*", "Button", true, false)
	var names: Array[String] = []
	var expected_names: Array[String] = []
	for button in buttons:
		names.append(button.name)
	expected_names.append("TutorialLaunch")
	_expect(names == expected_names, "%s offers exactly Launch Rescue" % page)
	var forward := _node("TutorialLaunch") as Button
	_expect(forward != null and forward.text == "Launch Rescue", "%s forward button is Launch Rescue" % page)

	# Layout: nothing overflows the modal or the 1152 x 648 base viewport, and buttons stay put.
	var consts: Dictionary = main.get_script().get_script_constant_map()
	var panel := (main.get("_menu_box") as Control).get_parent().get_parent() as Control
	var rect := panel.get_global_rect()
	var fits := true
	for button: Button in buttons:
		fits = fits and rect.encloses(button.get_global_rect()) and button.size.x >= button.get_minimum_size().x
	for label: Label in menu.find_children("*", "Label", true, false):
		fits = fits and label.size.y + 0.5 >= label.get_minimum_size().y and rect.grow(-20).encloses(label.get_global_rect()) \
			and label.get_line_count() == label.get_visible_line_count()
	fits = fits and body.get_minimum_size().y <= float(consts["TUTORIAL_BODY_HEIGHT"])
	_expect(VIEWPORT.encloses(rect) and fits, "%s fits its modal and the base viewport without clipping" % page)
	# Web builds have no system fonts, so every character must come from the bundled font.
	var missing := {}
	for control: Control in menu.find_children("*", "Label", true, false) + buttons:
		for character in String(control.get("text")):
			if not ThemeDB.fallback_font.has_char(character.unicode_at(0)):
				missing[character] = true
	_expect(missing.is_empty(), "%s uses only glyphs present in the bundled font (Web-safe)%s" % [page, "" if missing.is_empty() else ": " + str(missing.keys())])


## Everything gameplay-related must stay stopped for as long as the tutorial is open.
func _expect_frozen(context: String) -> void:
	await _physics_frames(6)
	var untouched := true
	for person in people:
		untouched = untouched and person.state == Survivor.State.ACTIVE and not person.discovered \
			and is_equal_approx(person.oxygen_remaining, person.oxygen_duration)
	_expect(is_equal_approx(manager.time_remaining, 240.0) and main.get("_stat_labels") == null,
		"%s: the (hidden) level clock has not started" % context)
	_expect(untouched, "%s: every oxygen tank stays full" % context)
	_expect(not manager.round_active and not boat.controls_enabled and not lighthouse.enabled and boat.velocity == Vector2.ZERO and not paused,
		"%s: the boat, the lighthouse and pause stay inactive" % context)


func _node(node_name: String) -> Node:
	var menu := main.get("_menu") as Control
	return null if menu == null else menu.find_child(node_name, true, false)


func _menu_contains(fragment: String) -> bool:
	var menu := main.get("_menu") as Control
	if menu == null:
		return false
	for label: Label in menu.find_children("*", "Label", true, false):
		if fragment.to_lower() in label.text.to_lower():
			return true
	return false


## Real mouse events need a window. The --headless display server never routes them to the
## GUI, so there the button's own signal stands in. The log header says which mode ran.
func _press(button: Button) -> void:
	if DisplayServer.get_name() == "headless":
		button.pressed.emit()
		return
	await process_frame # A page built this frame has no layout yet.
	await process_frame
	var point := button.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new() # A player always moves the pointer onto a button first.
	motion.position = point
	motion.global_position = point
	root.push_input(motion)
	await process_frame
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = point
		event.global_position = point
		event.pressed = pressed
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		root.push_input(event)


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


## Lets the level-start countdown play out (a little over 3 seconds of game time).
func _wait_for_intro() -> void:
	var guard := 0
	while main.get("_intro_active") == true and guard < 2400:
		await process_frame
		guard += 1
	_expect(main.get("_intro_active") == false, "The level-start countdown finishes")


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
	Input.action_release("move_up")
	print("TUTORIAL SUITE: %d/%d checks passed" % [checks - failures.size(), checks])
	if is_instance_valid(main):
		main.queue_free()
	quit(0 if failures.is_empty() else 1)
