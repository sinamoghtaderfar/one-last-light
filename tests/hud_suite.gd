extends SceneTree
## godot --headless --fixed-fps 60 --path . --script res://tests/hud_suite.gd
## Covers the top HUD and the player-facing guidance added on top of the rules:
## - the HUD has no clock and shows one heart per life (Levels 1-2: one, Levels 3-5: two);
## - losing a survivor hides a heart and plays the big heart-break, then either the GAME LOST
##   screen (last life) or, with a life left, a short freeze and the level carries on;
## - the Level 1 guided tour: movement hint when the boat arrives, E prompts at a survivor and
##   at the harbor, nothing of it in other levels;
## - the first-sighting warning (Levels 1 and 3) and which levels make the boat wait for the mouse;
## - the background no longer draws the fog and storm placeholders.
## Main's _process is off; the suite steps every animation by hand.

const STEP := 1.0 / 60.0
const LIVES := [1, 1, 2, 2, 3]
const REQUIRED_HUD_TEXT := ["ONE LAST LIGHT", "LEVEL 1"]
## The bar is icons now: none of the old captions remain.
const FORBIDDEN_HUD_TEXT := ["TIME", "ABOARD", "DELIVERED", "LOST", "STAR BANK", "SURVIVOR HEARTS", "LIVES", "FOG", "STORM", "EMERGENCY"]
const WIDGETS := ["Seats", "LifeHearts", "Progress", "Points"]

var checks: int = 0
var failures: Array[String] = []
var main: Node
var manager: RescueGameManager
var boat: RescueBoat
var harbor: Harbor
var tour: TourOverlay
var heart_break: HeartBreak
var sections_started: int = 0
var sections_done: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("Display: %s" % DisplayServer.get_name())
	await _boot(1)
	if main == null:
		_finish()
		return
	_check_hud_text_and_background()
	await _check_lives_per_level()
	await _boot(1)
	await _check_level_one_tour()
	await _boot(1)
	await _check_level_one_heart_break_and_retry()
	await _boot(3)
	await _check_level_three_two_lives()
	await _boot(2)
	await _check_no_tour_outside_level_one()
	await _check_boat_wait_by_level()
	_finish()


# --- helpers --------------------------------------------------------------------------------

func _boot(level_number: int) -> void:
	if is_instance_valid(main):
		main.queue_free()
		await process_frame
	paused = false
	main = null
	var scene := load("res://scenes/main.tscn") as PackedScene
	if scene == null:
		_expect(false, "Main scene loads")
		return
	main = scene.instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	manager = main.get("manager") as RescueGameManager
	boat = main.get("boat") as RescueBoat
	harbor = main.get("harbor") as Harbor
	tour = main.get("_tour") as TourOverlay
	heart_break = main.get("_heart_break") as HeartBreak
	if level_number != 1:
		manager.load_level(level_number - 1) # Fixture: jump straight to the level under test.


## Launch (or replay) the loaded level and play its countdown by hand.
func _launch() -> void:
	if main.get("_tutorial_open") == true:
		main.call("_launch_first_round")
	else:
		main.call("_begin_level_intro")
	var guard := 0
	while main.get("_intro_active") == true and guard < 400:
		main.call("_advance_intro", STEP)
		guard += 1


## Level 1-3: the first mouse move, then the 5 s wait and the 3 s sail-in, stepped by hand.
func _bring_boat_in() -> void:
	if main.get("_awaiting_mouse") == true:
		main.call("_on_first_mouse_move")
	var guard := 0
	while (main.get("_boat_delay") >= 0.0 or main.get("_late_arrival") == true) and guard < 1200:
		main.call("_advance_late_arrival", STEP)
		guard += 1


func _step_tour(seconds: float) -> void:
	var left := seconds
	while left > 0.0:
		main.call("_advance_tour", STEP)
		left -= STEP


func _step_heart_break() -> void:
	var guard := 0
	while heart_break.is_playing() and guard < 400:
		main.call("_advance_heart_break", STEP)
		guard += 1


func _lose(person: Survivor) -> void:
	person.oxygen_remaining = 0.001
	person._process(0.01)


func _hearts() -> Array:
	return main.get("_hearts")


func _visible_hearts() -> int:
	var count := 0
	for heart: LifeHeart in _hearts():
		if heart.visible:
			count += 1
	return count


func _menu_contains(fragment: String) -> bool:
	var menu := main.get("_menu") as Control
	if menu == null:
		return false
	for label: Label in menu.find_children("*", "Label", true, false):
		if fragment.to_lower() in label.text.to_lower():
			return true
	for button: Button in menu.find_children("*", "Button", true, false):
		if fragment.to_lower() in button.text.to_lower():
			return true
	return false


func _top_panel() -> Control:
	return (main.get("_hud") as CanvasLayer).get_child(0) as Control


# --- sections -------------------------------------------------------------------------------

func _check_hud_text_and_background() -> void:
	sections_started += 1
	var texts: Array[String] = []
	for label: Label in _top_panel().find_children("*", "Label", true, false):
		texts.append(label.text.to_upper())
	for wanted in REQUIRED_HUD_TEXT:
		_expect(wanted in texts, "The top HUD shows %s" % wanted)
	for banned in FORBIDDEN_HUD_TEXT:
		var found := false
		for text in texts:
			found = found or banned in text
		_expect(not found, "The top HUD no longer shows %s" % banned)
	for widget in WIDGETS:
		_expect(_top_panel().find_child(widget, false, false) != null, "The top bar has its %s icon widget" % widget)
	_expect(main.get("_stat_labels") == null, "There are no numeric caption readouts (and no clock)")
	var source: String = main.get_script().source_code
	_expect(not ("FOG" in source) and not ("STORM" in source) and not ("Weather areas" in source),
		"The background no longer draws the fog and storm placeholders")
	var no_clock := true
	for level in manager.levels:
		no_clock = no_clock and not level.time_limit_enabled
	_expect(no_clock, "No level fails on time")
	sections_done += 1


func _check_lives_per_level() -> void:
	sections_started += 1
	var panel := _top_panel().get_global_rect()
	for index in range(5):
		manager.load_level(index)
		var hearts := _hearts()
		var row := main.get("_hearts_row") as Control
		_expect(hearts.size() == LIVES[index] and row.get_child_count() == LIVES[index] and _visible_hearts() == LIVES[index],
			"Level %d shows %d full heart(s)" % [index + 1, LIVES[index]])
		var inside := true
		for heart: LifeHeart in hearts:
			inside = inside and panel.encloses(heart.get_global_rect())
		var clear := true
		for widget in ["Seats", "Progress", "Points"]:
			var rect := (_top_panel().find_child(widget, false, false) as Control).get_global_rect()
			for heart: LifeHeart in hearts:
				clear = clear and not rect.intersects(heart.get_global_rect())
		_expect(inside and clear, "Level %d: the hearts sit inside the bar and clear of the other icons" % (index + 1))
		var progress := main.get("_progress") as RescueProgress
		_expect(progress.total == manager.survivors_total and progress.required == manager.level.required_deliveries() and progress.delivered == 0,
			"Level %d: the progress bar counts %d survivors, %d needed to win" % [index + 1, manager.survivors_total, manager.level.required_deliveries()])
		_expect((main.get("_round_label") as Label).text == "LEVEL %d" % (index + 1) and _top_panel().find_child("LevelPips", true, false) == null,
			"Level %d: the bar says LEVEL %d, with no row of level dots" % [index + 1, index + 1])
	manager.load_level(0)
	sections_done += 1


func _check_level_one_tour() -> void:
	sections_started += 1
	_launch()
	_expect(manager.round_active and not boat.controls_enabled and not tour.move_showing, "Level 1: no movement hint before the boat arrives")
	var person := manager.survivors[0]
	person.discover()
	var banner := main.get("_banner") as Panel
	_expect(banner.visible and (main.get("_banner_label") as Label).text == "Careful! If one person drowns, the game is lost.",
		"Level 1: the first sighting shows the one-life warning")
	for i in range(int(5.2 / STEP)):
		main.call("_advance_banner", STEP)
	_expect(not banner.visible, "The warning disappears by itself after about 5 seconds")
	person.discovered = false
	person.discover()
	_expect(not banner.visible, "It is shown only once per attempt")

	_bring_boat_in()
	_expect(boat.controls_enabled and tour.move_showing, "When the boat has arrived, the movement hint appears")
	_step_tour(0.6)
	_expect(tour.visible and tour.move_alpha > 0.9 and tour.prompt_text == "", "The screen dims around the boat and the hint is fully shown, with no E prompt yet")
	_step_tour(2.0)
	_expect(tour.move_showing, "The hint waits for the player")
	Input.action_press("move_left")
	_step_tour(STEP)
	Input.action_release("move_left")
	_expect(not tour.move_showing, "The first steering key dismisses the hint")
	_step_tour(0.5)
	_expect(tour.move_alpha == 0.0, "The dim and the hint fade out")

	boat.global_position = person.global_position + Vector2(20, 0)
	_step_tour(0.3)
	_expect(tour.prompt_text == "Press E to pick up the survivor" and tour.prompt_alpha > 0.9, "Beside the survivor an E prompt says to pick them up")
	boat.global_position = person.global_position + Vector2(200, 0)
	_step_tour(0.3)
	_expect(tour.prompt_text == "", "Out of range the prompt goes away")
	boat.global_position = person.global_position + Vector2(20, 0)
	manager.try_interact()
	_step_tour(0.3)
	_expect(boat.passengers.size() == 1 and tour.prompt_text == "", "After pickup the pickup prompt is gone")
	_expect(not harbor.calling, "(main's _process is stepped by hand here)")
	main.call("_process", STEP)
	_expect(harbor.calling, "With every seat taken the harbor blinks to call the boat back")
	var other := manager.survivors[1]
	boat.global_position = other.global_position
	manager.try_interact()
	var bubble_found := false
	for node in main.get_node("World").get_children():
		bubble_found = bubble_found or (node is FloatingText and (node as FloatingText).text.begins_with("Boat full"))
	_expect(bubble_found and other.state == Survivor.State.ACTIVE, "E at another survivor with a full boat: a \"Boat full\" bubble, nobody boards")
	boat.global_position = harbor.global_position
	main.call("_process", STEP)
	_expect(not harbor.calling, "In the harbor the blinking stops")
	_step_tour(0.3)
	_expect(tour.prompt_text == "Press E to drop off the survivor", "Back at the harbor an E prompt says to drop them off")
	main.call("_toggle_pause")
	main.call("_advance_tour", STEP)
	_expect(not tour.visible, "The tour is hidden while paused")
	main.call("_toggle_pause")
	manager.try_interact()
	_expect(manager.delivered_count == 1 and manager.round_active, "Dropping off the first of two: Level 1 goes on")
	boat.global_position = manager.survivors[1].global_position
	manager.try_interact()
	boat.global_position = harbor.global_position
	manager.try_interact()
	_expect(manager.result == RescueGameManager.Result.VICTORY, "Dropping off the second wins Level 1")
	main.call("_advance_tour", STEP)
	_expect(not tour.visible and tour.prompt_text == "", "Nothing of the tour is left on the results screen")
	sections_done += 1


func _check_level_one_heart_break_and_retry() -> void:
	sections_started += 1
	_launch()
	_bring_boat_in()
	_lose(manager.survivors[0])
	_expect(not manager.round_active and manager.result == RescueGameManager.Result.SURVIVOR_LOST, "Level 1: one drowned survivor loses the game")
	_expect(_visible_hearts() == 0 and heart_break.is_playing() and main.get("_menu") == null,
		"The heart disappears from the bar and the big heart-break plays first")
	_expect(not paused, "Nothing needs freezing: the round is already over")
	main.call("_advance_heart_break", HeartBreak.RISE + HeartBreak.HOLD * 0.5)
	_expect(heart_break.is_playing() and main.get("_menu") == null, "Mid-animation there is still no menu")
	_step_heart_break()
	_expect(not heart_break.is_playing() and _menu_contains("GAME LOST") and _menu_contains("RETRY LEVEL 1"),
		"Then the GAME LOST screen offers RETRY LEVEL 1")
	_expect(_menu_contains("Level 1 has 1 life: one drowned survivor ends the level. Stars are only earned for a won level."),
		"It explains the life rule and why there are no stars")
	var retry := (main.get("_menu") as Control).find_child("ReplayButton", true, false) as Button
	retry.pressed.emit()
	_expect(_visible_hearts() == 1 and not heart_break.is_playing(), "Retry brings the heart back")
	_launch()
	_expect(manager.round_active and manager.lost_count == 0, "The retried level runs again")
	sections_done += 1


func _check_level_three_two_lives() -> void:
	sections_started += 1
	_launch()
	_expect(_visible_hearts() == 2, "Level 3 starts with two hearts")
	manager.survivors[0].discover()
	_expect((main.get("_banner_label") as Label).text == "Careful! If two people drown, the game is lost.",
		"Level 3: the first sighting shows the two-lives warning")
	_bring_boat_in()
	var other := manager.survivors[2]
	_lose(manager.survivors[0])
	_expect(manager.round_active and manager.result == RescueGameManager.Result.NONE and _visible_hearts() == 1,
		"The first loss costs one heart and the level goes on")
	_expect(heart_break.is_playing() and paused and main.get("_heart_freeze") == true and main.get("_menu") == null,
		"The heart-break plays over a frozen game, without a menu")
	var oxygen := other.oxygen_remaining
	await physics_frame
	await physics_frame
	_expect(is_equal_approx(oxygen, other.oxygen_remaining), "Oxygen does not drain during the heart-break")
	var esc := InputEventAction.new()
	esc.action = "pause_game"
	esc.pressed = true
	main.call("_unhandled_input", esc)
	_expect(main.get("_paused") == false, "Esc does not open the pause menu during the heart-break")
	_step_heart_break()
	_expect(not paused and main.get("_heart_freeze") == false and manager.round_active and main.get("_menu") == null,
		"Afterwards the game simply continues")
	_lose(manager.survivors[1])
	_expect(not manager.round_active and manager.result == RescueGameManager.Result.SURVIVOR_LOST and _visible_hearts() == 0,
		"The second loss ends Level 3")
	_step_heart_break()
	_expect(_menu_contains("GAME LOST") and _menu_contains("Two survivors drowned") and _menu_contains("RETRY LEVEL 3"),
		"The GAME LOST screen follows the second heart-break")
	sections_done += 1


func _check_no_tour_outside_level_one() -> void:
	sections_started += 1
	_launch()
	_bring_boat_in()
	main.call("_advance_tour", STEP)
	_expect(not tour.move_showing and not tour.visible, "Level 2 has no movement hint")
	var person := manager.survivors[0]
	person.discover()
	_expect(not (main.get("_banner") as Panel).visible, "Level 2 has no first-sighting warning")
	boat.global_position = person.global_position
	_step_tour(0.3)
	_expect(tour.prompt_text == "" and not tour.visible, "Level 2 has no E prompts")
	sections_done += 1


func _check_boat_wait_by_level() -> void:
	sections_started += 1
	for index in range(5):
		manager.load_level(index)
		_launch()
		var waits := index < 3
		_expect((not boat.controls_enabled and main.get("_awaiting_mouse") == true) == waits,
			"Level %d: after the countdown the boat %s" % [index + 1, "waits for the mouse" if waits else "is ready at once"])
		manager._end_round(RescueGameManager.Result.SURVIVOR_LOST)
		_step_heart_break()
	sections_done += 1


# --- utilities ------------------------------------------------------------------------------

func _expect(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("PASS: " + description)
	else:
		failures.append(description)
		push_error("FAIL: " + description)


func _finish() -> void:
	Input.action_release("move_left")
	_expect(sections_started == sections_done and sections_done >= 7, "Every test section ran to its end (%d of %d)" % [sections_done, sections_started])
	print("HUD SUITE: %d/%d checks passed" % [checks - failures.size(), checks])
	if is_instance_valid(main):
		main.queue_free()
	quit(0 if failures.is_empty() else 1)
