extends Node2D
## Assembles presentation; gameplay state belongs to GameManager and scene actors.

const SEA_RECT := Rect2(24, 116, 1104, 452)
const INK := Color("0d1c29")
const PANEL := Color("142937")
const TEXT := Color("e4ece8")
const MUTED := Color("91abb7")
const TEAL := Color("7fe0cc")
const GOLD := Color("ffda92")
## Top bar, left to right: the boat's seats, the lives, the level progress bar and the Light Points,
## all drawn as icons. The level dots and number sit top right.
const HEART_SIZE := 26.0
const HEART_PITCH := 34.0
const SEATS_POS := Vector2(16, 42)
const HEARTS_POS := Vector2(175, 49)
const PROGRESS_POS := Vector2(395, 42)
const POINTS_POS := Vector2(985, 42)
const MENU_WIDTH := 660.0
const SHOP_WIDTH := 900.0
## Seconds each "new upgrade" moment stays on screen at a level start.
const SHOWCASE_SECONDS := 3.2
const PROGRESS_CALLOUT_SECONDS := 6.5
const NUMBER_WORDS := ["ZERO", "ONE", "TWO", "THREE", "FOUR", "FIVE", "SIX", "SEVEN", "EIGHT", "NINE", "TEN"]
const TUTORIAL_BODY_HEIGHT := 120.0
const TUTORIAL_BUTTON_WIDTH := 170.0
const ARROW_SVG := '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 16 16"><path d="M2 8h11M9 3.5 13.5 8 9 12.5" fill="none" stroke="white" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>'
## Level-start intro: a three-second countdown while the main boat sails in from above the chart.
const INTRO_DURATION := 3.0
const GO_DURATION := 0.7
const COUNTDOWN_CENTER := Vector2(576, 226)
const ARRIVAL_START_Y := SEA_RECT.position.y - 76.0
## Pointer distance (px) that counts as the player's first deliberate mouse movement.
const FIRST_MOUSE_MOVE_DISTANCE := 24.0

@onready var manager: RescueGameManager = $GameManager
@onready var boat: RescueBoat = $World/PlayerBoat
@onready var lighthouse: Lighthouse = $World/Lighthouse
@onready var harbor: Harbor = $World/Harbor

var _hud: CanvasLayer
var _seats: SeatDisplay
var _progress: RescueProgress
var _points_badge: PointsBadge
var _context: Label
var _notice: Label
var _round_label: Label
var _menu: Control
var _menu_box: VBoxContainer
var _hearts: Array[LifeHeart] = []
var _hearts_row: Control
var _cue: MouseCue
var _bank_label: Label
var _shop_feedback: Label
var _shop_widgets: Dictionary = {}
var _continue_button: Button
var _notice_time: float = 0.0
var _notice_priority: int = 0
var _paused: bool = false
var _tutorial_open: bool = false
var _tutorial_step: int = 0
## The one-page briefing is shown the first time Level 1 is chosen on the level map.
var _briefing_seen: bool = false
var _arrow_textures: Dictionary = {}
var _countdown: Control
var _countdown_number: Label
var _countdown_caption: Label
var _intro_active: bool = false
var _intro_elapsed: float = 0.0
var _go_remaining: float = 0.0
## Late boat arrival (levels with boat_waits_for_mouse): waiting for the first mouse move,
## then a delay, then the same sail-in as the countdown, while the round is already running.
var _awaiting_mouse: bool = false
var _mouse_anchor := Vector2.ZERO
var _boat_delay: float = -1.0
var _late_arrival: bool = false
## A life was lost: the big heart-break plays. While it plays mid-level the game is frozen.
var _heart_break: HeartBreak
var _heart_freeze: bool = false
var _results_pending: bool = false
## Level 1 guided tour and the first-sighting warning.
var _tour_layer: CanvasLayer
var _tour: TourOverlay
var _banner: Panel
var _banner_label: Label
var _banner_time: float = 0.0
var _sighting_shown: bool = false
const BANNER_SECONDS := 5.0
var _banner_queue: Array[String] = []
var _last_full_bubble: int = -100000
## Level 1: the progress bar is explained while the boat is on its way.
var _callout: Panel
var _callout_time: float = 0.0
## Oxygen Boost button (only while the boost is armed for the level).
var _boost_button: BoostButton
## "New upgrade" moments shown when the boat is ready at a level start.
var _camera: Camera2D
var _showcase_queue: Array[String] = []
var _showcase_item: String = ""
var _showcase_time: float = 0.0
var _showcase_active: bool = false
var _showcase_panel: Panel
var _showcase_title: Label
var _showcase_text: Label


func _ready() -> void:
	_build_hud()
	_build_countdown()
	_build_cue()
	_build_tour_and_feedback()
	manager.notification.connect(_on_notification)
	manager.survivor_lost.connect(_on_survivor_lost)
	manager.survivor_spotted.connect(_on_survivor_spotted)
	manager.survivor_critical.connect(_on_survivor_critical)
	manager.survivor_boarded.connect(_on_survivor_boarded)
	manager.survivors_delivered.connect(_on_survivors_delivered)
	manager.boat_full_refused.connect(_on_boat_full_refused)
	manager.boost_applied.connect(_on_boost_applied)
	manager.state_changed.connect(_on_state_changed)
	manager.level_loaded.connect(_on_level_loaded)
	manager.round_started.connect(_on_round_started)
	manager.round_ended.connect(_show_results)
	manager.configure(boat, lighthouse, harbor, $World/Survivors)
	boat.visible = not _boat_waits() # Level 1 opens with the lighthouse only.
	_show_level_map()
	queue_redraw()


func _process(delta: float) -> void:
	_advance_intro(delta)
	_advance_late_arrival(delta)
	_advance_heart_break(delta)
	_advance_tour(delta)
	_advance_banner(delta)
	_advance_showcase(delta)
	_advance_callout(delta)
	_advance_boost_button(delta)
	_refresh_hud()
	harbor.set_boat_present(harbor.contains_point(boat.global_position))
	# Every seat taken: the harbor blinks until the boat is back there.
	harbor.set_calling(manager.round_active and boat.is_full() and not harbor.contains_point(boat.global_position))
	if not _paused and manager.round_active:
		_notice_time = maxf(_notice_time - delta, 0.0)
		if _notice_time == 0.0:
			_notice.text = ""
			_notice.self_modulate = MUTED


func _input(event: InputEvent) -> void:
	if _awaiting_mouse and event is InputEventMouseMotion and manager.round_active and not _paused:
		# Measured from where the pointer was when the wait began, so a tiny jiggle does not count.
		if (event as InputEventMouseMotion).position.distance_to(_mouse_anchor) >= FIRST_MOUSE_MOVE_DISTANCE:
			_on_first_mouse_move()


func _unhandled_input(event: InputEvent) -> void:
	# F11 switches between fullscreen and a window. The picture always scales to fit (canvas_items).
	if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_F11:
		var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("pause_game") and manager.round_active and not _heart_freeze and not _showcase_active:
		_toggle_pause()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("interact") and manager.round_active and not _paused:
		manager.try_interact()
		get_viewport().set_input_as_handled()


func _draw() -> void:
	draw_rect(Rect2(0, 0, 1152, 648), INK)
	draw_rect(SEA_RECT, Color("102b3d"))
	for x in range(48, 1128, 72):
		draw_line(Vector2(x, 117), Vector2(x, 567), Color(0.30, 0.52, 0.61, 0.065), 1.0)
	for y in range(136, 568, 72):
		draw_line(Vector2(25, y), Vector2(1127, y), Color(0.30, 0.52, 0.61, 0.065), 1.0)
	# Orientation marks and sea chart boundary remain readable at a glance.
	draw_rect(SEA_RECT, Color("35505d"), false, 1.0)
	draw_string(ThemeDB.fallback_font, Vector2(42, 144), "SEARCH AREA %02d  ·  %s" % [manager.level_number, _level_title()], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, MUTED)
	draw_string(ThemeDB.fallback_font, Vector2(1093, 146), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, MUTED)
	draw_line(Vector2(1098, 173), Vector2(1098, 152), MUTED, 1.0, true)
	draw_line(Vector2(1098, 152), Vector2(1093, 160), MUTED, 1.0, true)
	draw_line(Vector2(1098, 152), Vector2(1103, 160), MUTED, 1.0, true)


func _build_hud() -> void:
	_hud = CanvasLayer.new()
	_hud.name = "HUD"
	_hud.layer = 20
	add_child(_hud)
	var top := _panel_at(Rect2(16, 12, 1120, 94), PANEL)
	top.name = "TopBar"
	_hud.add_child(top)
	var title := _label("ONE LAST LIGHT", 16, MUTED)
	title.position = Vector2(16, 6)
	top.add_child(title)
	_round_label = _label("LEVEL 1", 14, TEXT)
	_round_label.name = "LevelLabel"
	_round_label.position = Vector2(990, 7)
	_round_label.size = Vector2(110, 18)
	_round_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	top.add_child(_round_label)
	_seats = SeatDisplay.new()
	_seats.name = "Seats"
	_seats.position = SEATS_POS
	top.add_child(_seats)
	_hearts_row = Control.new()
	_hearts_row.name = "LifeHearts"
	_hearts_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hearts_row.position = HEARTS_POS
	top.add_child(_hearts_row)
	_progress = RescueProgress.new()
	_progress.name = "Progress"
	_progress.position = PROGRESS_POS
	top.add_child(_progress)
	_points_badge = PointsBadge.new()
	_points_badge.name = "Points"
	_points_badge.position = POINTS_POS
	top.add_child(_points_badge)
	var bottom := _panel_at(Rect2(16, 580, 1120, 56), PANEL)
	_hud.add_child(bottom)
	_context = _label("", 15, TEXT)
	_context.position = Vector2(16, 6)
	_context.size.x = 1080
	bottom.add_child(_context)
	_notice = _label("", 12, Color.WHITE)
	_notice.position = Vector2(16, 31)
	_notice.size.x = 1080
	bottom.add_child(_notice)


## One heart per life of the current level (allowed_losses + 1). Rebuilt whenever a level is
## loaded; each drowned survivor then hides the rightmost heart still showing.
func _rebuild_hearts() -> void:
	for heart in _hearts:
		if is_instance_valid(heart):
			_hearts_row.remove_child(heart) # Out of the tree now, so counts never see a stale heart.
			heart.queue_free()
	_hearts.clear()
	var count: int = manager.level.lives() if manager.level != null else 1
	for index in range(count):
		var heart := LifeHeart.new()
		heart.name = "Life%d" % (index + 1)
		heart.size = Vector2(HEART_SIZE, HEART_SIZE)
		heart.position = Vector2(index * HEART_PITCH, 0)
		_hearts_row.add_child(heart)
		_hearts.append(heart)


func lives_left() -> int:
	return maxi(_hearts.size() - manager.lost_count, 0)


func _level_title() -> String:
	return manager.level.title.to_upper() if manager.level != null else ""


func _on_level_loaded(_level: LevelDefinition) -> void:
	_rebuild_hearts()
	_refresh_hud()
	queue_redraw()


func _on_state_changed() -> void:
	_refresh_hud()
	_refresh_shop_ui()


func _refresh_hud() -> void:
	if _seats == null or manager.level == null:
		return
	_seats.set_state(boat.capacity, boat.passengers.size())
	_progress.set_state(manager.survivors_total, manager.delivered_count, boat.passengers.size(), manager.lost_count, manager.level.required_deliveries())
	_points_badge.set_points(manager.points)
	for index in range(_hearts.size()):
		_hearts[index].visible = index < lives_left()
	_context.text = manager.context_hint()
	_round_label.text = "LEVEL %d" % manager.level_number
	if _boost_button != null:
		_boost_button.visible = manager.boost_armed and (manager.round_active or _intro_active)


func _on_notification(message: String, tone: String) -> void:
	var priority := 0 if tone == "info" else 1
	if tone == "danger":
		priority = 2
	if priority < _notice_priority and _notice_time > 0.0:
		return
	_notice_priority = priority
	_notice.text = message
	_notice_time = 2.5
	match tone:
		"success": _notice.self_modulate = TEAL
		"warning": _notice.self_modulate = GOLD
		"danger": _notice.self_modulate = Color("fa958a")
		_: _notice.self_modulate = MUTED


func _on_round_started() -> void:
	if manager.level.show_mouse_cue:
		_cue.play(manager.level.boat_waits_for_mouse)
	_notice_time = 0.0
	_notice_priority = 0
	_paused = false
	_tutorial_open = false
	get_tree().paused = false
	_clear_menu()


## Pre-launch briefing: one short page, then Launch Rescue. It is still built as a list of pages
## (title, icon, lines), so more pages can be added later without touching the screen code.
func _tutorial_content() -> Array:
	return [
		{
			"title": "Your Mission",
			"icon": 0,
			"lines": [
				"People are drowning. Rescue them with your boat.",
				"Steer with WASD or the arrow keys. Aim the lighthouse with your mouse.",
				"Press E to pick people up, and E at the harbor to drop them off.",
			],
		},
	]


## The tutorial is pure UI. Until Launch Rescue, the manager keeps the clock, oxygen,
## both boats and the lighthouse stopped, and every gameplay input checks round_active.
func _show_tutorial() -> void:
	_tutorial_open = true
	_tutorial_step = 0
	_render_tutorial_step()


func _render_tutorial_step() -> void:
	var step: Dictionary = _tutorial_content()[_tutorial_step]
	var page_count := _tutorial_content().size()
	_open_menu()
	# A single-page briefing needs no step counter or progress bar.
	if page_count > 1:
		var counter := _add_menu_label("Step %d of %d" % [_tutorial_step + 1, page_count], 14, TEAL)
		counter.name = "TutorialStepLabel"
	var icon := TutorialIcon.new(step["icon"])
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_menu_box.add_child(icon)
	var title := _add_menu_label(step["title"], 32, TEXT)
	title.name = "TutorialTitle"
	if page_count > 1:
		_menu_box.add_child(_tutorial_progress(_tutorial_step))
	_menu_box.add_child(_tutorial_body(step["lines"]))
	_menu_box.add_child(HSeparator.new())
	_menu_box.add_child(_tutorial_navigation(_tutorial_step))


func _tutorial_progress(current: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "TutorialProgress"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	for index in range(_tutorial_content().size()):
		var state := "upcoming"
		var color := Color("2d4655")
		if index < current:
			state = "done"
			color = TEAL.darkened(0.3)
		elif index == current:
			state = "current"
			color = GOLD
		var segment := Panel.new()
		segment.name = "Segment%d" % (index + 1)
		segment.custom_minimum_size = Vector2(56, 6)
		segment.mouse_filter = Control.MOUSE_FILTER_IGNORE
		segment.set_meta("state", state)
		segment.add_theme_stylebox_override("panel", _style(color, color, 3))
		row.add_child(segment)
	return row


## A fixed-height block keeps the navigation buttons in the same place on every step.
func _tutorial_body(lines: Array) -> VBoxContainer:
	var body := VBoxContainer.new()
	body.name = "TutorialBody"
	body.alignment = BoxContainer.ALIGNMENT_CENTER
	body.custom_minimum_size.y = TUTORIAL_BODY_HEIGHT
	body.add_theme_constant_override("separation", 12)
	for line in lines:
		var label := _label(line, 17, TEXT)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.add_child(label)
	return body


## Back sits left (absent on step 1); Next or Launch Rescue always sits right.
func _tutorial_navigation(step: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "TutorialNav"
	row.custom_minimum_size.y = 50 # Launch Rescue is taller; this stops the modal shifting on step 4.
	row.add_theme_constant_override("separation", 12)
	if step > 0:
		var back := _button("Back", _tutorial_back)
		back.name = "TutorialBack"
		back.custom_minimum_size.x = TUTORIAL_BUTTON_WIDTH
		_add_button_arrow(back, false)
		row.add_child(back)
	var spacer := Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	var is_last := step == _tutorial_content().size() - 1
	var forward := _button("Launch Rescue" if is_last else "Next", _launch_first_round if is_last else _tutorial_next)
	forward.name = "TutorialLaunch" if is_last else "TutorialNext"
	forward.custom_minimum_size.x = TUTORIAL_BUTTON_WIDTH
	if is_last:
		_emphasize_button(forward)
	else:
		_add_button_arrow(forward, true)
	row.add_child(forward)
	forward.grab_focus.call_deferred()
	return row


func _tutorial_next() -> void:
	_go_to_tutorial_step(_tutorial_step + 1)


func _tutorial_back() -> void:
	_go_to_tutorial_step(_tutorial_step - 1)


func _go_to_tutorial_step(step: int) -> void:
	if not _tutorial_open:
		return
	_tutorial_step = clampi(step, 0, _tutorial_content().size() - 1)
	_render_tutorial_step()


func _launch_first_round() -> void:
	# Only the open tutorial may launch, so a repeated press cannot start a second round.
	if not _tutorial_open or manager.round_active:
		return
	_tutorial_open = false
	_briefing_seen = true
	_begin_level_intro()


## --- Level map (main menu) --------------------------------------------------------------------
## Every level as a card: its best rating, PLAY / REPLAY, or locked until the level before it has at
## least one star. The furthest open level is marked NEXT. Opening the map leaves any running level.
func _show_level_map() -> void:
	_leave_level()
	_open_menu(SHOP_WIDTH)
	_menu_box.add_theme_constant_override("separation", 10)
	var heading := _add_menu_label("ONE LAST LIGHT", 28, GOLD)
	heading.name = "MapHeading"
	var total := manager.economy.total_stars()
	var summary := _add_menu_label("Choose a level   ·   Stars: %d / %d   ·   Light Points: %d" % [total, manager.levels.size() * 3, manager.points], 15, TEXT)
	summary.name = "MapSummary"
	var grid := GridContainer.new()
	grid.name = "LevelGrid"
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	_menu_box.add_child(grid)
	var next := manager.highest_unlocked()
	var focus: Button = null
	for level in manager.levels:
		var card := _level_card(level, next)
		grid.add_child(card)
		if level.level_number == next:
			focus = card.find_child("PlayButton_%d" % level.level_number, true, false) as Button
	_add_menu_label("A level opens when you win the one before it. Replaying pays only for stars you did not have yet.", 12, MUTED)
	if focus != null:
		focus.grab_focus()


func _level_card(level: LevelDefinition, next: int) -> PanelContainer:
	var number := level.level_number
	var open := manager.is_unlocked(number)
	var best: int = manager.economy.best_stars.get(number, 0)
	var card := PanelContainer.new()
	card.name = "LevelCard_%d" % number
	card.custom_minimum_size = Vector2(162, 0)
	var state := "locked" if not open else ("next" if number == next and best == 0 else ("done" if best > 0 else "open"))
	card.set_meta("state", state)
	var border := Color("2d4655")
	if state == "next":
		border = GOLD
	elif state == "done":
		border = TEAL
	var style := _style(Color("1c3d49") if open else Color("142a33"), border, 8)
	style.set_border_width_all(2 if state == "next" else 1)
	card.add_theme_stylebox_override("panel", style)
	card.modulate = Color.WHITE if open else Color(0.6, 0.62, 0.64, 0.85)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	card.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	margin.add_child(box)
	var tag := _label("NEXT" if state == "next" else ("LEVEL %d" % number), 12, GOLD if state == "next" else MUTED)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(tag)
	var number_label := _label(str(number), 30, TEXT if open else MUTED)
	number_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(number_label)
	var title := _label(level.title, 13, TEXT if open else MUTED)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var row := StarRow.new()
	row.name = "Stars"
	row.stars = best
	row.previous_best = best
	row.star_size = 11.0
	row.spacing = 26.0
	row.custom_minimum_size = Vector2(100, 28)
	box.add_child(row)
	var info := _label("", 11, MUTED)
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.text = "%d survivors · %d %s" % [level.survivor_count(), level.lives(), "life" if level.lives() == 1 else "lives"] if open else "Win Level %d first" % (number - 1)
	box.add_child(info)
	var button := _button("PLAY" if open and best == 0 else ("REPLAY" if open else "LOCKED"), _select_level.bind(number))
	button.name = "PlayButton_%d" % number
	button.custom_minimum_size.y = 34
	button.disabled = not open
	if state == "next":
		_emphasize_button(button)
		button.custom_minimum_size.y = 38
	box.add_child(button)
	return card


func _select_level(number: int) -> void:
	if _intro_active or not manager.select_level(number):
		return
	if number == 1 and not _briefing_seen:
		_show_tutorial()
	elif manager.economy.has_boost:
		_ask_boost()
	else:
		_begin_level_intro()


## Stops whatever is running (countdown, level, pause, boat wait, effects) without a result.
func _leave_level() -> void:
	_intro_active = false
	_go_remaining = 0.0
	_countdown.visible = false
	_cue.stop()
	_reset_late_arrival()
	_reset_feedback()
	if manager.round_active:
		manager.abort_round()
	_tutorial_open = false
	_paused = false
	get_tree().paused = false


## --- Level results and campaign screens -------------------------------------------------------
## The manager decides what happened; these screens only show it and forward the player's choice.
func _show_results() -> void:
	_cue.stop()
	_reset_late_arrival()
	_tour.clear()
	if _heart_break.is_playing():
		_results_pending = true # The failure screen follows the heart-break.
		return
	match manager.result:
		RescueGameManager.Result.VICTORY:
			if manager.campaign_complete:
				_show_campaign_complete()
			else:
				_show_level_complete()
		_:
			_show_failure()


func _stars_text(count: int) -> String:
	return "%d star%s" % [count, "" if count == 1 else "s"]


func _show_level_complete() -> void:
	var level := manager.level
	_open_menu()
	var heading := _add_menu_label("LEVEL %d COMPLETE" % level.level_number, 14, TEAL)
	heading.name = "ResultHeading"
	var row := StarRow.new()
	row.name = "StarRow"
	row.stars = manager.level_stars
	row.previous_best = manager.level_stars if manager.level_points == 0 else _previous_best_stars()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_menu_box.add_child(row)
	var reasons := _add_menu_label(_rating_text(), 13, MUTED)
	reasons.name = "RatingReasons"
	var earned := _add_menu_label("+%d Light Points" % manager.level_points if manager.level_points > 0 else "No new stars this time, so no new points", 24 if manager.level_points > 0 else 16, GOLD)
	earned.name = "PointsEarned"
	_add_menu_label("%d of %d %s delivered   ·   %d lost" % [manager.delivered_count, manager.survivors_total, "survivor" if manager.survivors_total == 1 else "survivors", manager.lost_count], 15, TEXT)
	_bank_label = _add_menu_label("", 17, GOLD)
	_bank_label.name = "BankLabel"
	_menu_box.add_child(HSeparator.new())
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	_menu_box.add_child(buttons)
	var shop := _button("SHOP", _show_shop)
	shop.name = "ShopButton"
	shop.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(shop)
	var map := _button("LEVELS", _show_level_map)
	map.name = "LevelsButton"
	map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(map)
	_continue_button = _button("CONTINUE TO LEVEL %d" % (level.level_number + 1), _continue_campaign)
	_continue_button.name = "ContinueButton"
	_continue_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(_continue_button)
	_refresh_shop_ui()
	_continue_button.grab_focus()


## The rating held before this attempt, recovered from the points it paid.
func _previous_best_stars() -> int:
	var after: int = manager.level_stars
	for stars in range(after, -1, -1):
		if manager.economy.points_for(after) - manager.economy.points_for(stars) == manager.level_points:
			return stars
	return 0


func _rating_text() -> String:
	var parts: Array[String] = ["Finished: +1 star"]
	parts.append("Nobody drowned: %s" % ("+1 star" if manager.lost_count == 0 else "missed"))
	parts.append("Everyone saved before their air turned red: %s" % ("missed" if manager.any_critical else "+1 star"))
	return "   ·   ".join(parts)


## Every item, always visible. Grey when it cannot be bought (locked, needs its first phase, or too
## expensive), in colour as soon as the points are there, OWNED once bought.
func _show_shop() -> void:
	if not manager.can_shop():
		return
	_open_menu(SHOP_WIDTH)
	_menu_box.add_theme_constant_override("separation", 8)
	var heading := _add_menu_label("SHOP", 24, GOLD)
	heading.name = "ShopHeading"
	_bank_label = _add_menu_label("", 17, GOLD)
	_bank_label.name = "BankLabel"
	var grid := GridContainer.new()
	grid.name = "ShopGrid"
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	_menu_box.add_child(grid)
	for entry in ShopCatalog.ITEMS:
		grid.add_child(_shop_card(entry))
	_shop_feedback = _add_menu_label("", 13, MUTED)
	_shop_feedback.name = "ShopFeedback"
	var back := _button("BACK", _show_level_complete)
	back.name = "ShopBack"
	_menu_box.add_child(back)
	_refresh_shop_ui()
	back.grab_focus()


func _shop_card(entry: Dictionary) -> PanelContainer:
	var card := PanelContainer.new()
	card.name = "ShopCard_%s" % entry["id"]
	card.custom_minimum_size = Vector2(202, 0)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	card.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	margin.add_child(box)
	var icon := ShopIcon.new(int(entry["kind"]))
	icon.name = "Icon"
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(icon)
	var title := _label(entry["title"], 15, TEXT)
	title.name = "Title"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var detail := _label(entry["detail"], 12, MUTED)
	detail.name = "Detail"
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.custom_minimum_size = Vector2(186, 32)
	box.add_child(detail)
	var status := _label("", 12, GOLD)
	status.name = "Status"
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(status)
	var button := _button("", _on_shop_pressed.bind(entry["id"]))
	button.name = "BuyButton_%s" % entry["id"]
	button.custom_minimum_size.y = 34
	button.add_theme_font_size_override("font_size", 13)
	box.add_child(button)
	_shop_widgets[entry["id"]] = {"card": card, "button": button, "status": status, "icon": icon}
	return card


func _on_shop_pressed(id: String) -> void:
	# The manager is the single authority: a second press, a locked item or too few points is refused.
	if manager.buy(id) and is_instance_valid(_shop_feedback):
		var entry := ShopCatalog.item(id)
		if entry["kind"] == ShopCatalog.Kind.BOOST:
			_shop_feedback.text = "Oxygen Boost bought! You will be asked to take it into the next level."
		else:
			_shop_feedback.text = "%s bought! You will see it in action at the start of the next level." % entry["title"]
		_shop_feedback.add_theme_color_override("font_color", TEAL)
	_refresh_shop_ui()


## Keeps every price, state and the balance equal to the real economy.
func _refresh_shop_ui() -> void:
	if is_instance_valid(_bank_label) and manager.level != null and manager.result == RescueGameManager.Result.VICTORY:
		_bank_label.text = "Your Light Points: %d" % manager.points
	for id in _shop_widgets:
		var widgets: Dictionary = _shop_widgets[id]
		var button: Button = widgets["button"]
		if not is_instance_valid(button):
			continue
		var entry := ShopCatalog.item(id)
		var reason := manager.shop_status(id)
		var card: PanelContainer = widgets["card"]
		var status: Label = widgets["status"]
		var active := reason == ""
		match reason:
			"owned":
				status.text = "Owned"
				button.text = "OWNED"
			"level":
				status.text = "Unlocks at Level %d" % entry["unlock_level"]
				button.text = "LOCKED"
			"requires":
				status.text = "Needs %s first" % ShopCatalog.title_of(entry["requires"])
				button.text = "LOCKED"
			"points":
				status.text = "Need %d more points" % (int(entry["price"]) - manager.points)
				button.text = "%d POINTS" % entry["price"]
			_:
				status.text = "Ready to buy"
				button.text = "BUY  ·  %d POINTS" % entry["price"]
		button.disabled = not active
		card.set_meta("state", "owned" if reason == "owned" else ("active" if active else "grey"))
		card.add_theme_stylebox_override("panel", _style(Color("1c3d49") if active else Color("142a33"),
			TEAL if reason == "owned" else (GOLD if active else Color("2d4655")), 8))
		card.modulate = Color.WHITE if active or reason == "owned" else Color(0.6, 0.62, 0.64, 0.85)
		(widgets["icon"] as ShopIcon).active = active or reason == "owned"


func _show_failure() -> void:
	_open_menu()
	var heading := _add_menu_label("GAME LOST  ·  LEVEL %d" % manager.level_number, 14, Color("fa958a"))
	heading.name = "ResultHeading"
	var reason := ""
	if manager.result == RescueGameManager.Result.TIME_RAN_OUT:
		reason = "Time ran out"
	else:
		if manager.lost_ids.size() > 1:
			reason = "%s survivors drowned" % NUMBER_WORDS[mini(manager.lost_ids.size(), NUMBER_WORDS.size() - 1)].capitalize()
		elif not manager.lost_ids.is_empty():
			reason = "Survivor %02d was lost" % manager.lost_ids[0]
		else:
			reason = "A survivor was lost"
	var why := _add_menu_label(reason, 28, Color("fa958a"))
	why.name = "FailureReason"
	if manager.result == RescueGameManager.Result.SURVIVOR_LOST:
		var lives := manager.level.lives()
		var rule := _add_menu_label("Level %d has %d %s: %s ends the level. Stars are only earned for a won level." % [
			manager.level_number, lives, "life" if lives == 1 else "lives",
			"one drowned survivor" if lives == 1 else "%s drowned survivors" % NUMBER_WORDS[mini(lives, NUMBER_WORDS.size() - 1)].to_lower()], 14, MUTED)
		rule.name = "LivesRule"
		rule.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_add_menu_label("%d of %d delivered   ·   %d lost   ·   %d still in the water   ·   %d aboard" % [manager.delivered_count, manager.survivors_total, manager.lost_count, manager.active_count(), boat.passengers.size()], 16, TEXT)
	_bank_label = _add_menu_label("", 18, GOLD)
	_bank_label.name = "BankLabel"
	_bank_label.text = "Light Points: %d  ·  upgrades are kept" % manager.points
	_menu_box.add_child(HSeparator.new())
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	_menu_box.add_child(buttons)
	var map := _button("LEVELS", _show_level_map)
	map.name = "LevelsButton"
	map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(map)
	var retry := _button("RETRY LEVEL %d" % manager.level_number, _retry_round)
	retry.name = "ReplayButton"
	retry.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(retry)
	retry.grab_focus()


func _show_campaign_complete() -> void:
	var economy := manager.economy
	_open_menu()
	var heading := _add_menu_label("ALL %s LEVELS COMPLETE" % NUMBER_WORDS[mini(manager.levels.size(), NUMBER_WORDS.size() - 1)], 24, GOLD)
	heading.name = "ResultHeading"
	var message := _add_menu_label("Every survivor made it home. The light stayed on.", 17, TEXT)
	message.name = "VictoryMessage"
	var stats := _add_menu_label("Survivors rescued: %d     Stars: %d / %d     Light Points earned: %d" % [economy.total_rescued, economy.total_stars(), manager.levels.size() * 3, economy.total_points_earned], 16, TEAL)
	stats.name = "CampaignStats"
	var upgrades := _add_menu_label(_upgrade_summary(), 14, MUTED)
	upgrades.name = "UpgradeSummary"
	upgrades.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_menu_box.add_child(HSeparator.new())
	var map := _button("LEVELS", _show_level_map)
	map.name = "LevelsButton"
	_menu_box.add_child(map)
	var restart := _button("RESTART CAMPAIGN", _restart_campaign)
	restart.name = "RestartButton"
	_menu_box.add_child(restart)
	restart.grab_focus()


func _upgrade_summary() -> String:
	var economy := manager.economy
	if economy.purchases.is_empty():
		return "Upgrades bought: none.   Light Points left: %d" % economy.points
	var parts: Array[String] = []
	for purchase in economy.purchases:
		parts.append(ShopCatalog.title_of(purchase["id"]))
	return "Upgrades bought: " + ", ".join(parts) + ".   Light Points left: %d" % economy.points


## Forward from a won level. The manager refuses a second call, so a double click cannot skip a level.
func _continue_campaign() -> void:
	if _intro_active:
		return
	if manager.advance_level():
		if manager.economy.has_boost:
			_ask_boost()
		else:
			_begin_level_intro()


## Before a level, if the player owns an unused Oxygen Boost: bring it along?
func _ask_boost() -> void:
	_open_menu()
	var heading := _add_menu_label("LEVEL %d" % manager.level_number, 14, TEAL)
	heading.name = "ResultHeading"
	var icon := ShopIcon.new(ShopCatalog.Kind.BOOST)
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_menu_box.add_child(icon)
	var question := _add_menu_label("Take the Oxygen Boost into this level?", 24, TEXT)
	question.name = "BoostQuestion"
	var detail := _add_menu_label("When someone's air runs low you can click it once: +15 s oxygen for everyone in the water.", 14, MUTED)
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_menu_box.add_child(HSeparator.new())
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	_menu_box.add_child(buttons)
	var yes := _button("YES, BRING IT", _answer_boost.bind(true))
	yes.name = "BoostYes"
	yes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(yes)
	var no := _button("NO, SAVE IT", _answer_boost.bind(false))
	no.name = "BoostNo"
	no.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(no)
	yes.grab_focus()


func _answer_boost(take: bool) -> void:
	if _intro_active:
		return
	manager.boost_armed = take
	_begin_level_intro()


func _retry_round() -> void:
	_begin_level_intro()


func _restart_campaign() -> void:
	if _intro_active:
		return
	manager.restart_campaign()
	_begin_level_intro()


func _toggle_pause() -> void:
	_paused = not _paused
	get_tree().paused = _paused
	if _paused:
		_open_menu()
		_add_menu_label("OPERATIONS PAUSED", 12, TEAL)
		_add_menu_label("Take a bearing", 32, TEXT)
		_add_menu_label("The level clock, oxygen, lighthouse and boat are paused.", 16, MUTED)
		var resume := _button("RESUME RESCUE", _toggle_pause)
		_menu_box.add_child(resume)
		var map := _button("LEVELS  (leave this level)", _show_level_map)
		map.name = "LevelsButton"
		_menu_box.add_child(map)
		_add_menu_label("WASD / ARROWS  Move  ·  E  Rescue / unload  ·  ESC  Resume", 12, MUTED)
		resume.grab_focus()
	else:
		_clear_menu()


## --- Level start intro --------------------------------------------------------------------
## Runs from Launch Rescue (and every Replay) until the last countdown tick. The manager has
## prepared the round but keeps it stopped, so the clock, oxygen, both boats and the lighthouse
## stay inactive. One elapsed-time value drives the number, the boat and the overlay, so the
## sequence takes three seconds at any frame rate. Gameplay is switched on exactly once, in
## _finish_intro, after the boat has reached its berth.
func _begin_level_intro() -> void:
	if _intro_active:
		return
	_clear_menu()
	_cue.stop()
	_reset_late_arrival()
	_reset_feedback()
	manager.prepare_round()
	_intro_elapsed = 0.0
	_go_remaining = 0.0
	_intro_active = true
	_apply_arrival(0.0)
	boat.visible = not _boat_waits()
	_update_countdown_display()


func _advance_intro(delta: float) -> void:
	if _intro_active:
		_intro_elapsed = minf(_intro_elapsed + delta, INTRO_DURATION)
		if _intro_elapsed < INTRO_DURATION:
			if not _boat_waits():
				_apply_arrival(delta)
			_update_countdown_display()
		else:
			_finish_intro()
	elif _go_remaining > 0.0:
		_go_remaining = maxf(_go_remaining - delta, 0.0)
		_update_go_display()


func _finish_intro() -> void:
	_intro_active = false
	if _boat_waits():
		# The round starts with the lighthouse only; the boat stays out of sight above the chart.
		manager.begin_round()
		boat.controls_enabled = false
		_awaiting_mouse = true
		_mouse_anchor = get_viewport().get_mouse_position()
		_go_remaining = GO_DURATION
		_update_go_display()
		return
	# Land exactly on the berth with the normal start heading, so activation causes no jump.
	boat.global_position = manager.boat_spawn
	boat.heading = PI
	boat.velocity = Vector2.ZERO
	boat.queue_redraw()
	manager.begin_round()
	_go_remaining = GO_DURATION
	_update_go_display()
	_on_boat_ready()


## --- Lives, heart-break, tour and warnings ----------------------------------------------------
func _build_tour_and_feedback() -> void:
	_tour_layer = CanvasLayer.new()
	_tour_layer.name = "TourLayer"
	_tour_layer.layer = 19 # Above the world, below the HUD bars and menus.
	add_child(_tour_layer)
	_tour = TourOverlay.new()
	_tour.name = "Tour"
	_tour.boat = boat
	_tour_layer.add_child(_tour)
	_banner = _panel_at(Rect2(276, 122, 600, 44), PANEL)
	_banner.name = "WarningBanner"
	var border := _style(Color(0.08, 0.13, 0.18, 0.95), GOLD, 8)
	border.set_border_width_all(2)
	_banner.add_theme_stylebox_override("panel", border)
	_banner.visible = false
	_hud.add_child(_banner)
	_banner_label = _label("", 17, GOLD)
	_banner_label.name = "WarningText"
	_banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_banner_label.position = Vector2.ZERO
	_banner_label.size = _banner.size
	_banner.add_child(_banner_label)
	_build_callout()
	_build_showcase()
	_boost_button = BoostButton.new()
	_boost_button.name = "BoostButton"
	_boost_button.position = Vector2(36, 452)
	_boost_button.visible = false
	_boost_button.activated.connect(_on_boost_pressed)
	_hud.add_child(_boost_button)
	_camera = Camera2D.new()
	_camera.name = "Camera"
	_camera.position = Vector2(576, 324)
	_camera.limit_left = 0
	_camera.limit_top = 0
	_camera.limit_right = 1152
	_camera.limit_bottom = 648
	add_child(_camera)
	_camera.make_current()
	_heart_break = HeartBreak.new()
	_heart_break.name = "HeartBreak"
	_hud.add_child(_heart_break)
	_heart_break.finished.connect(_on_heart_break_finished)


func _reset_feedback() -> void:
	_tour.clear()
	_banner_time = 0.0
	_banner.visible = false
	_banner_queue.clear()
	_callout_time = 0.0
	_callout.visible = false
	_progress.highlight = 0.0
	if _showcase_active:
		_end_showcase(false)
	_sighting_shown = false
	_results_pending = false
	if _heart_freeze:
		_heart_freeze = false
		get_tree().paused = _paused
	if _heart_break.is_playing():
		_heart_break.finish()


func _on_survivor_lost(survivor: Survivor) -> void:
	var game_over := manager.lost_count > manager.level.allowed_losses
	var left := lives_left()
	var caption := "Survivor %02d drowned" % survivor.survivor_id
	if not game_over:
		caption += "  ·  %d %s left" % [left, "life" if left == 1 else "lives"]
		# Mid-level loss: freeze the game for the moment, then play on.
		_heart_freeze = true
		get_tree().paused = true
	_tour.clear()
	_heart_break.play(caption)


func _advance_heart_break(delta: float) -> void:
	_heart_break.advance(delta)


func _on_heart_break_finished() -> void:
	if _heart_freeze:
		_heart_freeze = false
		get_tree().paused = _paused
		_on_notification("You lost a life. Keep going: one more loss ends the game." if lives_left() == 1 else "You lost a life. Keep going.", "warning")
	if _results_pending:
		_results_pending = false
		_show_results()


func _on_survivor_spotted(_survivor: Survivor) -> void:
	if _sighting_shown or manager.level.first_sighting_message == "":
		return
	_sighting_shown = true
	_show_banner(manager.level.first_sighting_message)


## Shows a gold banner under the top bar, or queues it while the progress callout uses that spot.
func _show_banner(text: String, immediate: bool = false) -> void:
	if _callout_time > 0.0 and not immediate:
		_banner_queue.append(text)
		return
	_banner_label.text = text
	_banner_time = BANNER_SECONDS
	_banner.visible = true
	_banner.modulate.a = 1.0


func _advance_banner(delta: float) -> void:
	if _banner_time <= 0.0:
		if not _banner_queue.is_empty() and _callout_time <= 0.0:
			_show_banner(_banner_queue.pop_front())
		return
	if not _paused and not _heart_freeze:
		_banner_time = maxf(_banner_time - delta, 0.0)
	_banner.modulate.a = clampf(_banner_time / 0.6, 0.0, 1.0)
	_banner.visible = _banner_time > 0.0


## The tour only ever shows in a running, unpaused level that has show_tour.
func _advance_tour(delta: float) -> void:
	var live := manager.round_active and not _paused and not _heart_freeze and not _showcase_active and manager.level.show_tour
	_tour.visible = live
	if not live:
		return
	if _tour.move_showing and boat.controls_enabled and Input.get_vector("move_left", "move_right", "move_up", "move_down") != Vector2.ZERO:
		_tour.dismiss_move_hint()
	var prompt := ""
	if boat.controls_enabled and not _tour.move_showing:
		if harbor.contains_point(boat.global_position) and not boat.passengers.is_empty():
			prompt = "Press E to drop off the survivor%s" % ("" if boat.passengers.size() == 1 else "s")
		elif not boat.is_full() and manager.nearest_survivor() != null:
			prompt = "Press E to pick up the survivor"
	_tour.set_prompt(prompt)
	_tour.advance(delta)


## --- Progress callout (Level 1) ------------------------------------------------------------
func _build_callout() -> void:
	_callout = _panel_at(Rect2(366, 112, 420, 62), PANEL)
	_callout.name = "ProgressCallout"
	var border := _style(Color(0.08, 0.13, 0.18, 0.96), GOLD, 8)
	border.set_border_width_all(2)
	_callout.add_theme_stylebox_override("panel", border)
	_callout.visible = false
	_hud.add_child(_callout)
	var first := _label("This bar shows your rescue progress.", 15, GOLD)
	first.name = "CalloutTitle"
	first.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	first.position = Vector2(0, 8)
	first.size = Vector2(420, 20)
	_callout.add_child(first)
	var second := _label("Green: saved   ·   Red: drowned   ·   Fill it with green to win!", 13, TEXT)
	second.name = "CalloutText"
	second.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	second.position = Vector2(0, 33)
	second.size = Vector2(420, 20)
	_callout.add_child(second)


func _start_progress_callout() -> void:
	_callout_time = PROGRESS_CALLOUT_SECONDS
	_callout.visible = true
	_callout.modulate.a = 1.0


func _advance_callout(delta: float) -> void:
	if _callout_time <= 0.0:
		return
	if not _paused and not _heart_freeze and not _showcase_active:
		_callout_time = maxf(_callout_time - delta, 0.0)
	_callout.modulate.a = clampf(_callout_time / 0.5, 0.0, 1.0)
	_callout.visible = _callout_time > 0.0
	_progress.highlight = (0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.008)) * clampf(_callout_time / 0.5, 0.0, 1.0)
	_progress.queue_redraw()


## --- Short speech bubbles over the boat -------------------------------------------------------
func _on_survivor_boarded(_survivor: Survivor) -> void:
	_float_text("Got you!", Color("6fe39a"))


func _on_survivors_delivered(count: int) -> void:
	_float_text("Bye! You're safe." if count == 1 else "Bye, everyone! You're safe.", HudIcons.GOLD)


func _on_boat_full_refused() -> void:
	var now := Time.get_ticks_msec()
	if now - _last_full_bubble < 900:
		return # Holding or hammering E does not stack bubbles.
	_last_full_bubble = now
	_float_text("Boat full! Unload at the harbor first.", Color("fa958a"))


func _float_text(text: String, color: Color) -> void:
	var bubble := FloatingText.new(text, color)
	var half := ThemeDB.fallback_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x * 0.5 + 18.0
	bubble.position = boat.global_position + Vector2(0, -52)
	bubble.position.x = clampf(bubble.position.x, 30.0 + half, 1122.0 - half) # Keep it inside the chart.
	$World.add_child(bubble)


## --- Oxygen Boost ----------------------------------------------------------------------------
func _on_survivor_critical(_survivor: Survivor) -> void:
	if manager.boost_armed:
		_boost_button.nudge()


func _on_boost_pressed() -> void:
	if _paused or _heart_freeze or _showcase_active:
		return
	manager.activate_boost()


func _on_boost_applied(seconds: float) -> void:
	_boost_button.visible = false
	_show_banner("+%d s OXYGEN FOR EVERYONE IN THE WATER!" % int(seconds), true)


func _advance_boost_button(delta: float) -> void:
	_boost_button.visible = manager.boost_armed and manager.round_active
	if _boost_button.visible and not _paused:
		_boost_button.advance(delta)


## --- New upgrades, shown once when the boat is ready ------------------------------------------
func _build_showcase() -> void:
	_showcase_panel = _panel_at(Rect2(316, 452, 520, 96), PANEL)
	_showcase_panel.name = "UpgradeShowcase"
	var border := _style(Color(0.06, 0.13, 0.18, 0.96), GOLD, 10)
	border.set_border_width_all(2)
	_showcase_panel.add_theme_stylebox_override("panel", border)
	_showcase_panel.visible = false
	_hud.add_child(_showcase_panel)
	_showcase_title = _label("", 24, GOLD)
	_showcase_title.name = "ShowcaseTitle"
	_showcase_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_showcase_title.position = Vector2(0, 14)
	_showcase_title.size = Vector2(520, 30)
	_showcase_panel.add_child(_showcase_title)
	_showcase_text = _label("", 16, TEXT)
	_showcase_text.name = "ShowcaseText"
	_showcase_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_showcase_text.position = Vector2(0, 54)
	_showcase_text.size = Vector2(520, 24)
	_showcase_panel.add_child(_showcase_text)


## The boat has its controls: show what was bought since the last level (once), then the tour.
func _on_boat_ready() -> void:
	_showcase_queue.assign(manager.economy.unshown)
	manager.economy.unshown.clear()
	if _showcase_queue.is_empty():
		_after_showcase()
		return
	_showcase_active = true
	get_tree().paused = true
	_next_showcase()


func _next_showcase() -> void:
	if _showcase_queue.is_empty():
		_end_showcase(true)
		return
	_showcase_item = _showcase_queue.pop_front()
	_showcase_time = 0.0
	var entry := ShopCatalog.item(_showcase_item)
	_showcase_panel.visible = true
	match int(entry.get("kind", -1)):
		ShopCatalog.Kind.CAPACITY:
			_showcase_title.text = "GREAT! YOU ADDED A SEAT"
			_showcase_text.text = "Your boat now carries %d survivors per trip." % boat.capacity
			_seats.highlight_seat = boat.capacity - 1
		ShopCatalog.Kind.SPEED:
			_showcase_title.text = "ENGINE UPGRADED!"
			_showcase_text.text = "Your boat is now %d%% faster." % roundi(boat.speed_level * boat.speed_bonus_per_level * 100.0)
			boat.process_mode = Node.PROCESS_MODE_ALWAYS
			boat.showcase_exhaust = true
		ShopCatalog.Kind.LIGHT:
			_showcase_title.text = "BRIGHTER LIGHTHOUSE!"
			_showcase_text.text = "The beam now reaches further and covers more sea."
		_:
			_showcase_title.text = "%s READY!" % String(entry.get("title", "UPGRADE")).to_upper()
			_showcase_text.text = String(entry.get("detail", ""))


## Steps the current moment: the camera glides in on what changed, holds, and glides back.
func _advance_showcase(delta: float) -> void:
	if not _showcase_active:
		return
	_showcase_time += delta
	var kind := int(ShopCatalog.item(_showcase_item).get("kind", -1))
	var focus := Vector2(576, 324)
	var zoom_to := 1.0
	if kind == ShopCatalog.Kind.SPEED or kind == ShopCatalog.Kind.CAPACITY:
		focus = boat.global_position
		zoom_to = 2.0 if kind == ShopCatalog.Kind.SPEED else 1.5
	elif kind == ShopCatalog.Kind.LIGHT:
		focus = lighthouse.global_position
		zoom_to = 1.5
	var k := smoothstep(0.0, 0.6, _showcase_time) * (1.0 - smoothstep(SHOWCASE_SECONDS - 0.6, SHOWCASE_SECONDS, _showcase_time))
	_camera.position = Vector2(576, 324).lerp(focus, k)
	_camera.zoom = Vector2.ONE * lerpf(1.0, zoom_to, k)
	_showcase_panel.modulate.a = clampf(minf(_showcase_time / 0.3, (SHOWCASE_SECONDS - _showcase_time) / 0.3), 0.0, 1.0)
	if _showcase_time >= SHOWCASE_SECONDS:
		_finish_showcase_item()
		_next_showcase()


func _finish_showcase_item() -> void:
	boat.showcase_exhaust = false
	boat.process_mode = Node.PROCESS_MODE_INHERIT
	boat.queue_redraw()
	_seats.highlight_seat = -1
	_seats.queue_redraw()
	_camera.position = Vector2(576, 324)
	_camera.zoom = Vector2.ONE


## Also used by tests to skip the moments. continue_level: go on to the tour afterwards.
func _end_showcase(continue_level: bool) -> void:
	_finish_showcase_item()
	_showcase_queue.clear()
	_showcase_item = ""
	_showcase_active = false
	_showcase_panel.visible = false
	get_tree().paused = _paused or _heart_freeze
	if continue_level:
		_after_showcase()


func _after_showcase() -> void:
	if manager.level.show_tour:
		_tour.show_move_hint()


func _boat_waits() -> bool:
	return manager.level != null and manager.level.boat_waits_for_mouse


func _reset_late_arrival() -> void:
	if _awaiting_mouse or _boat_delay >= 0.0 or _late_arrival:
		boat.global_position = manager.boat_spawn # Never left parked above the chart.
		boat.heading = PI
		boat.velocity = Vector2.ZERO
	_awaiting_mouse = false
	_boat_delay = -1.0
	_late_arrival = false
	boat.visible = true


func _on_first_mouse_move() -> void:
	_awaiting_mouse = false
	_cue.dismiss()
	if manager.level.show_progress_callout:
		_start_progress_callout()
	_boat_delay = manager.level.boat_delay_after_mouse


## Counts down the delay after the first mouse move, then sails the boat in exactly like the
## countdown arrival. Both halves stop while the game is paused or the round is over.
func _advance_late_arrival(delta: float) -> void:
	if _paused or _heart_freeze or _showcase_active or not manager.round_active:
		return
	if _boat_delay >= 0.0:
		_boat_delay -= delta
		if _boat_delay < 0.0:
			_boat_delay = -1.0
			_late_arrival = true
			_intro_elapsed = 0.0
			_apply_arrival(0.0)
			boat.visible = true
	elif _late_arrival:
		_intro_elapsed = minf(_intro_elapsed + delta, INTRO_DURATION)
		if _intro_elapsed < INTRO_DURATION:
			_apply_arrival(delta)
		else:
			_late_arrival = false
			boat.global_position = manager.boat_spawn
			boat.heading = PI
			boat.velocity = Vector2.ZERO
			boat.controls_enabled = true
			boat.queue_redraw()
			_on_notification("Your rescue boat is here. Steer with WASD or the arrow keys.", "success")
			_on_boat_ready()


## The boat is moved by this script while its player controls are off. Its speed, collision and
## handling settings are never touched; velocity is only set so the normal wake is drawn.
func _apply_arrival(delta: float) -> void:
	var progress := sin(_intro_elapsed / INTRO_DURATION * PI * 0.5) # Decelerates into the berth.
	var next := _arrival_position(progress)
	boat.velocity = (next - boat.global_position) / delta if delta > 0.0 else Vector2.ZERO
	boat.global_position = next
	boat.heading = _arrival_heading(progress)
	boat.queue_redraw()


## Bezier control points: start above the chart's top edge, then slide down the open water east
## of the reefs and bend into the berth, well clear of the reefs, the island and the dock.
func _arrival_points() -> PackedVector2Array:
	var berth := manager.boat_spawn
	return PackedVector2Array([
		Vector2(berth.x + 36.0, ARRIVAL_START_Y),
		Vector2(berth.x + 68.0, 140.0),
		Vector2(berth.x + 56.0, 262.0),
		berth,
	])


func _arrival_position(progress: float) -> Vector2:
	var points := _arrival_points()
	return points[0].bezier_interpolate(points[1], points[2], points[3], progress)


## Faces the direction of travel, then swings round to the normal start heading in the last
## moments, when the boat has all but stopped at its berth.
func _arrival_heading(progress: float) -> float:
	var points := _arrival_points()
	var travel := points[0].bezier_derivative(points[1], points[2], points[3], progress).angle()
	return lerp_angle(travel, PI, smoothstep(0.85, 1.0, progress))


func _build_cue() -> void:
	_cue = MouseCue.new()
	_cue.name = "MouseCue"
	_cue.start_delay = GO_DURATION + 0.1 # Appears once the GO! flash has cleared the same patch of sea.
	lighthouse.add_child(_cue)


func _build_countdown() -> void:
	_countdown = Control.new()
	_countdown.name = "Countdown"
	_countdown.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_countdown.mouse_filter = Control.MOUSE_FILTER_IGNORE # Never a modal; the world stays visible.
	_countdown.visible = false
	_hud.add_child(_countdown)
	_countdown_caption = _label("RESCUE BEGINS IN", 16, TEAL)
	_countdown_caption.name = "CountdownCaption"
	_countdown_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_countdown_caption.size = Vector2(400, 24)
	_countdown_caption.position = COUNTDOWN_CENTER + Vector2(-200, -104)
	_countdown.add_child(_countdown_caption)
	_countdown_number = _label("3", 150, GOLD)
	_countdown_number.name = "CountdownNumber"
	_countdown_number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_countdown_number.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_countdown_number.add_theme_constant_override("outline_size", 12)
	_countdown_number.add_theme_color_override("font_outline_color", INK)
	_countdown_number.size = Vector2(440, 220)
	_countdown_number.position = COUNTDOWN_CENTER - _countdown_number.size * 0.5
	_countdown_number.pivot_offset = _countdown_number.size * 0.5
	_countdown.add_child(_countdown_number)


## Each number pops in slightly large, settles, and dims a little before the next one.
func _update_countdown_display() -> void:
	var tick := fposmod(_intro_elapsed, 1.0)
	_countdown.visible = true
	_countdown_caption.visible = true
	_countdown_number.text = str(clampi(ceili(INTRO_DURATION - _intro_elapsed), 1, ceili(INTRO_DURATION)))
	_countdown_number.add_theme_color_override("font_color", GOLD)
	_countdown_number.scale = Vector2.ONE * lerpf(1.3, 1.0, ease(minf(tick / 0.25, 1.0), 0.35))
	_countdown_number.modulate.a = lerpf(1.0, 0.4, smoothstep(0.7, 1.0, tick))


## "GO!" appears after gameplay has already started and fades out; it never delays anything.
func _update_go_display() -> void:
	_countdown.visible = _go_remaining > 0.0
	if not _countdown.visible:
		return
	var fade := _go_remaining / GO_DURATION
	_countdown_caption.visible = false
	_countdown_number.text = "GO!"
	_countdown_number.add_theme_color_override("font_color", TEAL)
	_countdown_number.scale = Vector2.ONE * lerpf(1.35, 1.0, fade)
	_countdown_number.modulate.a = clampf(fade * 1.6, 0.0, 1.0)


func _open_menu(width: float = MENU_WIDTH) -> void:
	_clear_menu()
	_menu = Control.new()
	_menu.name = "RoundMenu"
	_menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hud.add_child(_menu)
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.05, 0.09, 0.88)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_menu.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_menu.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = width
	panel.add_theme_stylebox_override("panel", _style(PANEL, Color("41616b"), 12))
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 30)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	panel.add_child(margin)
	_menu_box = VBoxContainer.new()
	_menu_box.add_theme_constant_override("separation", 14)
	margin.add_child(_menu_box)


func _clear_menu() -> void:
	_shop_feedback = null
	_shop_widgets.clear()
	_continue_button = null
	_bank_label = null
	if is_instance_valid(_menu):
		_menu.hide()
		_menu.queue_free()
	_menu = null


func _add_menu_label(content: String, font_size: int, color: Color) -> Label:
	var label := _label(content, font_size, color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_menu_box.add_child(label)
	return label


func _label(content: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = content
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _button(content: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = content
	button.custom_minimum_size.y = 44
	button.add_theme_font_size_override("font_size", 15)
	button.add_theme_color_override("font_color", TEXT)
	button.add_theme_color_override("font_disabled_color", Color("75838a"))
	button.add_theme_stylebox_override("normal", _style(Color("254a54"), Color("43717a"), 6))
	button.add_theme_stylebox_override("hover", _style(Color("32606a"), TEAL, 6))
	button.add_theme_stylebox_override("pressed", _style(Color("1b3944"), TEAL, 6))
	button.add_theme_stylebox_override("focus", _style(Color(0, 0, 0, 0), GOLD, 6))
	button.add_theme_stylebox_override("disabled", _style(Color("1b303c"), Color("304650"), 6))
	button.pressed.connect(callback)
	return button


## The bundled UI font has no arrow glyphs and Web builds have no system fonts to fall
## back on, so "←" and "→" would render as missing-glyph boxes there. Draw them instead.
func _add_button_arrow(button: Button, points_right: bool) -> void:
	if not _arrow_textures.has(points_right):
		var image := Image.new()
		if image.load_svg_from_string(ARROW_SVG, 1.5) != OK:
			return # No arrow is better than a broken one; the button text still works.
		if not points_right:
			image.flip_x()
		_arrow_textures[points_right] = ImageTexture.create_from_image(image)
	button.icon = _arrow_textures[points_right]
	button.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT if points_right else HORIZONTAL_ALIGNMENT_LEFT
	for state in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		button.add_theme_color_override("icon_%s_color" % state, TEXT)


## Gold-ringed call to action; used only for Launch Rescue.
func _emphasize_button(button: Button) -> void:
	button.custom_minimum_size.y = 50
	button.add_theme_font_size_override("font_size", 17)
	button.add_theme_color_override("font_color", Color.WHITE)
	for state in ["normal", "hover", "pressed"]:
		var fill := Color("2c6a63") if state == "normal" else (Color("39877d") if state == "hover" else Color("21514c"))
		var style := _style(fill, GOLD, 6)
		style.set_border_width_all(2)
		button.add_theme_stylebox_override(state, style)
	var focus := _style(Color(0, 0, 0, 0), Color.WHITE, 6)
	focus.set_border_width_all(2)
	button.add_theme_stylebox_override("focus", focus)


func _panel_at(rect: Rect2, color: Color) -> Panel:
	var panel := Panel.new()
	panel.position = rect.position
	panel.size = rect.size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _style(color, Color("2d4655"), 8))
	return panel


func _style(background: Color, border: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	return style


## Small tutorial pictograms drawn from primitives, so no image assets are needed.
class TutorialIcon extends Control:
	const GOLD_TONE := Color("ffda92")
	const TEAL_TONE := Color("7fe0cc")
	const HULL_TONE := Color("e4ece8")
	var kind: int = 0

	func _init(icon_kind: int) -> void:
		kind = icon_kind
		custom_minimum_size = Vector2(56, 56)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := Vector2(28, 28)
		match kind:
			0: # Lifebuoy: the mission is to bring everyone back.
				for quarter in range(4):
					var start := quarter * PI * 0.5 + 0.2
					draw_arc(c, 19.0, start, start + PI * 0.5 - 0.4, 12, GOLD_TONE if quarter % 2 == 0 else TEAL_TONE, 7.0, true)
				draw_arc(c, 11.0, 0.0, TAU, 32, Color("2d4655"), 1.5, true)
			1: # Lighthouse beam sweeping across a survivor marker.
				draw_colored_polygon(PackedVector2Array([Vector2(12, 28), Vector2(52, 10), Vector2(52, 46)]), Color(GOLD_TONE, 0.28))
				draw_colored_polygon(PackedVector2Array([Vector2(5, 46), Vector2(19, 46), Vector2(16, 14), Vector2(8, 14)]), HULL_TONE)
				draw_rect(Rect2(5, 6, 14, 8), GOLD_TONE)
				draw_arc(Vector2(42, 28), 4.0, 0.0, TAU, 16, TEAL_TONE, 2.5, true)
			2: # Main boat with its harbor ring.
				draw_arc(c, 24.0, 0.0, TAU, 40, Color(TEAL_TONE, 0.45), 1.5, true)
				draw_colored_polygon(PackedVector2Array([Vector2(10, 28), Vector2(46, 28), Vector2(39, 39), Vector2(17, 39)]), HULL_TONE)
				draw_rect(Rect2(21, 19, 13, 9), TEAL_TONE)
				draw_line(Vector2(28, 11), Vector2(28, 19), GOLD_TONE, 2.0, true)
			3: # Upgrade: a star above a rising chevron.
				var star := PackedVector2Array()
				for point in range(10):
					var radius := 17.0 if point % 2 == 0 else 7.5
					star.append(Vector2(28, 22) + Vector2.from_angle(-PI * 0.5 + point * PI / 5.0) * radius)
				draw_colored_polygon(star, GOLD_TONE)
				draw_polyline(PackedVector2Array([Vector2(14, 52), Vector2(28, 42), Vector2(42, 52)]), TEAL_TONE, 3.0, true)
