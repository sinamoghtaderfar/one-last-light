extends SceneTree
## godot --headless --fixed-fps 60 --path . --script res://tests/tutorial_suite.gd
## Covers the four-step pre-launch tutorial: content, Next/Back navigation, progress indicator,
## layout fit, the frozen game state while it is open, input isolation, the one-time launch,
## and the hand-off to pause, results, upgrades and replay.

const VIEWPORT := Rect2(0, 0, 1152, 648)
## Independent copy of the required wording, so an accidental content edit is caught.
const SPEC := [
	{
		"title": "Your Mission",
		"lines": [
			"Rescue every survivor across 5 levels, one level at a time.",
			"Deliver them all to the harbor before the 4-minute timer runs out.",
			"If a survivor runs out of oxygen, the level fails. You can replay it right away.",
		],
	},
	{
		"title": "Find Survivors",
		"lines": [
			"Move your mouse to aim the lighthouse beam.",
			"The light reveals survivors and their remaining oxygen.",
			"Contacts disappear 3 seconds after leaving the light, unless your boat is close enough to detect them.",
		],
	},
	{
		"title": "Rescue & Deliver",
		"lines": [
			"Use WASD or the arrow keys to steer your rescue boat.",
			"Press E near a survivor to pick them up, even if they are not currently visible.",
			"Your boat starts with room for 1 survivor. Return to the harbor and press E to deliver.",
		],
	},
	{
		"title": "Earn Stars & Upgrade",
		"lines": [
			"Each survivor you deliver earns 3 stars.",
			"Between levels, spend stars to carry more survivors or sail faster. Upgrades stay for the whole campaign.",
			"Press Esc to pause or resume the game.",
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
var first_panel_rect := Rect2()
var first_forward_rect := Rect2()
var first_back_rect := Rect2()


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
	await _check_forward_and_back()
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
	_expect(boat.capacity == 1 and manager.stars_per_survivor == 3 and durations_ok,
		"Tutorial numbers match the rules: 1 starting seat, 3 stars per delivered survivor, 3 seconds of visibility memory")
	var all_text := ""
	for step: Dictionary in main.call("_tutorial_content"):
		all_text += step["title"] + " " + " ".join(step["lines"]) + " "
	for removed in ["Emergency", "emergency", "Right-click", "15 survivors", "up to 2 survivors"]:
		_expect(not (removed in all_text), "Tutorial text no longer mentions '%s'" % removed)


func _check_startup() -> void:
	_expect(main.get("_tutorial_open") == true and main.get("_tutorial_step") == 0, "Game startup opens tutorial step 1")
	_expect(not manager.round_active and round_starts == 0, "No round has started at startup")
	await _expect_page(0)
	await _expect_frozen("Step 1")
	_expect(_node("TutorialBack") == null, "Back is unavailable on step 1")
	main.call("_tutorial_back")
	_expect(main.get("_tutorial_step") == 0, "Back cannot move before step 1")


func _check_forward_and_back() -> void:
	# The first trip uses real mouse clicks when a window exists, to exercise the buttons themselves.
	for step in range(1, 4):
		await _press(_node("TutorialNext") as Button)
		_expect(main.get("_tutorial_step") == step, "Pressing Next advances exactly one step, to step %d" % (step + 1))
		await _expect_page(step)
		await _expect_frozen("Step %d" % (step + 1))
	main.call("_tutorial_next")
	_expect(main.get("_tutorial_step") == 3 and _node("TutorialNext") == null, "Step 4 is the last page and has no Next")
	for step in [2, 1, 0]:
		await _press(_node("TutorialBack") as Button)
		_expect(main.get("_tutorial_step") == step, "Pressing Back returns exactly one step, to step %d" % (step + 1))
		await _expect_page(step)
	# The second trip presses the buttons through their signal, as keyboard activation would.
	for step in range(1, 4):
		(_node("TutorialNext") as Button).pressed.emit()
		_expect(main.get("_tutorial_step") == step, "Next works again after going back, to step %d" % (step + 1))
		await _expect_page(step)
	await _expect_frozen("After navigating forward and back")


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
	_expect(not paused and main.get("_tutorial_open") == true and main.get("_tutorial_step") == 3 and _node("TutorialLaunch") != null,
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
	_expect(launch != null and launch.text == "Launch Rescue", "Step 4 offers Launch Rescue")
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
	_expect(manager.round_active and boat.controls_enabled and lighthouse.enabled and manager.level_number == 1 and people.size() == 1,
		"Launch activates Level 1 (one survivor), the boat and the lighthouse")
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

	# Finish Level 1: deliver the one survivor. The level completes and offers the first upgrade.
	boat.global_position = harbor.global_position
	_key(KEY_E)
	_expect(manager.delivered_count == 1 and manager.result == RescueGameManager.Result.VICTORY and manager.level_stars == 3 and manager.stars == 3,
		"Delivering the only Level 1 survivor wins the level and earns 3 stars")
	_expect(_menu_contains("LEVEL 1 COMPLETE") and _menu_contains("You earned 3 stars!"), "The results screen shows LEVEL 1 COMPLETE with the stars earned")
	var upgrade := _node("OfferButton_l1_capacity") as Button
	_expect(upgrade != null and not upgrade.disabled and upgrade.text == "UPGRADE — 3 STARS", "Earned stars unlock the capacity upgrade in the popup")
	upgrade.pressed.emit()
	upgrade.pressed.emit() # A duplicate press must not buy twice.
	_expect(manager.economy.capacity == 2 and manager.economy.stars == 0, "The upgrade is bought once, at its price")

	var next: Button = _node("ContinueButton") as Button
	_expect(next != null and next.text == "CONTINUE TO LEVEL 2", "After buying, the popup continues to Level 2")
	var starts := round_starts
	next.pressed.emit()
	_expect(main.get("_intro_active") == true and not manager.round_active and round_starts == starts and manager.level_number == 2,
		"Continue prepares Level 2 and runs the countdown before activating it")
	await _wait_for_intro()
	_expect(manager.round_active and round_starts == starts + 1 and manager.level_number == 2 and manager.survivors.size() == 2,
		"Level 2 then starts with its two survivors")
	_expect(main.get("_tutorial_open") == false and main.get("_menu") == null and _node("TutorialTitle") == null,
		"Continuing does not reopen the tutorial")
	_expect(boat.capacity == 2, "The purchased capacity carries into Level 2")
	# Fail Level 2 on the clock and replay it: the upgrade stays.
	manager._process(manager.time_remaining)
	_expect(not manager.round_active and manager.result == RescueGameManager.Result.TIME_RAN_OUT and _menu_contains("Time ran out"),
		"The failure screen appears when the timer expires")
	var replay := _node("ReplayButton") as Button
	_expect(replay != null and replay.text == "REPLAY LEVEL 2", "The failure screen offers Replay Level 2")
	starts = round_starts
	replay.pressed.emit()
	_expect(main.get("_intro_active") == true and not manager.round_active and round_starts == starts and manager.level_number == 2,
		"Replay prepares Level 2 and runs the countdown before activating it")
	await _wait_for_intro()
	_expect(manager.round_active and round_starts == starts + 1 and manager.level_number == 2, "Replay then starts Level 2")
	_expect(manager.time_remaining > 239.9 and manager.time_remaining <= 240.0 and boat.capacity == 2,
		"Replay restores the clock and keeps the purchased capacity")


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
	_expect((_node("TutorialStepLabel") as Label).text == "Step %d of 4" % (step + 1), "%s shows 'Step %d of 4'" % [page, step + 1])
	_expect((_node("TutorialTitle") as Label).text == spec["title"], "%s is titled '%s'" % [page, spec["title"]])
	var body := _node("TutorialBody") as Control
	var shown: Array = []
	for line: Label in body.get_children():
		shown.append(line.text)
	_expect(shown == spec["lines"], "%s shows the required text" % page)

	var segments := _node("TutorialProgress").get_children()
	var states: Array[String] = []
	var wanted: Array[String] = []
	for index in range(4):
		states.append(segments[index].get_meta("state") if index < segments.size() else "missing")
		wanted.append("done" if index < step else ("current" if index == step else "upcoming"))
	_expect(segments.size() == 4 and states == wanted, "%s progress segments read %s" % [page, ", ".join(wanted)])

	var buttons := menu.find_children("*", "Button", true, false)
	var names: Array[String] = []
	var expected_names: Array[String] = []
	for button in buttons:
		names.append(button.name)
	if step > 0:
		expected_names.append("TutorialBack")
	expected_names.append("TutorialLaunch" if step == 3 else "TutorialNext")
	_expect(names == expected_names, "%s offers exactly %s" % [page, " + ".join(expected_names)])
	var back := _node("TutorialBack") as Button
	var forward := (_node("TutorialLaunch") if step == 3 else _node("TutorialNext")) as Button
	_expect(back == null or (back.text == "Back" and back.icon != null), "%s Back carries a drawn left arrow" % page)
	_expect(forward != null and (forward.text == "Launch Rescue" if step == 3 else (forward.text == "Next" and forward.icon != null)),
		"%s forward button is %s" % [page, "Launch Rescue" if step == 3 else "Next with a drawn right arrow"])

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
	if step == 0:
		first_panel_rect = rect
		first_forward_rect = forward.get_global_rect()
	if step == 1:
		first_back_rect = back.get_global_rect()
	_expect(rect.is_equal_approx(first_panel_rect) and forward.get_global_rect().is_equal_approx(first_forward_rect)
		and (back == null or step == 0 or back.get_global_rect().is_equal_approx(first_back_rect)),
		"%s keeps the modal and its buttons in the same place" % page)

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
	var clock_text := ((main.get("_stat_labels") as Dictionary)["TIME"] as Label).text
	_expect(is_equal_approx(manager.time_remaining, 240.0) and clock_text == "4:00", "%s: the timer stays at 4:00" % context)
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
