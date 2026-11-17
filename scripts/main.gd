extends Node2D
## Assembles presentation; gameplay state belongs to GameManager and scene actors.

const SEA_RECT := Rect2(24, 116, 1104, 452)
const INK := Color("0d1c29")
const PANEL := Color("142937")
const TEXT := Color("e4ece8")
const MUTED := Color("91abb7")
const TEAL := Color("7fe0cc")
const GOLD := Color("ffda92")
const TUTORIAL_BODY_HEIGHT := 196.0
const TUTORIAL_BUTTON_WIDTH := 170.0
const ARROW_SVG := '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 16 16"><path d="M2 8h11M9 3.5 13.5 8 9 12.5" fill="none" stroke="white" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>'
## Pre-launch tutorial content. Each step is one page; "icon" selects a TutorialIcon drawing.
const TUTORIAL_STEPS := [
	{
		"title": "Your Mission",
		"icon": 0,
		"lines": [
			"Rescue the 15 survivors before the 4-minute timer runs out.",
			"You can lose up to 2 survivors. A third loss ends the mission.",
		],
	},
	{
		"title": "Find Survivors",
		"icon": 1,
		"lines": [
			"Move your mouse to aim the lighthouse beam.",
			"The light reveals survivors and their remaining oxygen.",
			"Contacts disappear 3 seconds after leaving the light, unless your boat is close enough to detect them.",
		],
	},
	{
		"title": "Rescue & Deliver",
		"icon": 2,
		"lines": [
			"Use WASD or the arrow keys to steer your rescue boat.",
			"Press E near a survivor to pick them up, even if they are not currently visible.",
			"Your boat carries 2 survivors. Return to the harbor and press E to deliver them.",
			"Each survivor delivered by your main boat earns 3 stars.",
		],
	},
	{
		"title": "Emergency Rescue",
		"icon": 3,
		"lines": [
			"Right-click a visible survivor to dispatch the emergency boat.",
			"It automatically navigates around obstacles, rescues the survivor, and returns to harbor.",
			"Emergency rescues earn 0 stars and do not deduct existing stars.",
			"Press Esc to pause or resume the game.",
		],
	},
]
## Level-start intro: a three-second countdown while the main boat sails in from above the chart.
const INTRO_DURATION := 3.0
const GO_DURATION := 0.7
const COUNTDOWN_CENTER := Vector2(576, 226)
const ARRIVAL_START_Y := SEA_RECT.position.y - 76.0

@onready var manager: RescueGameManager = $GameManager
@onready var boat: RescueBoat = $World/PlayerBoat
@onready var emergency: EmergencyBoat = $World/EmergencyBoat
@onready var lighthouse: Lighthouse = $World/Lighthouse
@onready var harbor: Harbor = $World/Harbor
var survivors: Array[Survivor] = []

var _hud: CanvasLayer
var _stat_labels: Dictionary = {}
var _context: Label
var _notice: Label
var _round_label: Label
var _menu: Control
var _menu_box: VBoxContainer
var _emergency_label: Label
var _purchase_feedback: Label
var _speed_button: Button
var _bank_label: Label
var _notice_time: float = 0.0
var _notice_priority: int = 0
var _paused: bool = false
var _tutorial_open: bool = false
var _tutorial_step: int = 0
var _arrow_textures: Dictionary = {}
var _countdown: Control
var _countdown_number: Label
var _countdown_caption: Label
var _intro_active: bool = false
var _intro_elapsed: float = 0.0
var _go_remaining: float = 0.0


func _ready() -> void:
	for node in $World/Survivors.get_children():
		if node is Survivor:
			survivors.append(node)
	_build_hud()
	_build_countdown()
	manager.notification.connect(_on_notification)
	manager.state_changed.connect(_refresh_hud)
	manager.round_started.connect(_on_round_started)
	manager.round_ended.connect(_show_results)
	manager.configure(boat, lighthouse, harbor, survivors, emergency)
	_show_tutorial()
	queue_redraw()


func _process(delta: float) -> void:
	_advance_intro(delta)
	_refresh_hud()
	harbor.set_boat_present(harbor.contains_point(boat.global_position))
	if not _paused and manager.round_active:
		_notice_time = maxf(_notice_time - delta, 0.0)
		if _notice_time == 0.0:
			_notice.text = ""
			_notice.self_modulate = MUTED


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause_game") and manager.round_active:
		_toggle_pause()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("interact") and manager.round_active and not _paused:
		manager.try_interact()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		if manager.round_active and not _paused:
			manager.dispatch_at(get_canvas_transform().affine_inverse() * event.position)
			get_viewport().set_input_as_handled()


func _draw() -> void:
	draw_rect(Rect2(0, 0, 1152, 648), INK)
	draw_rect(SEA_RECT, Color("102b3d"))
	for x in range(48, 1128, 72):
		draw_line(Vector2(x, 117), Vector2(x, 567), Color(0.30, 0.52, 0.61, 0.065), 1.0)
	for y in range(136, 568, 72):
		draw_line(Vector2(25, y), Vector2(1127, y), Color(0.30, 0.52, 0.61, 0.065), 1.0)
	# Weather areas are navigation placeholders, with no hidden handling penalties.
	for index in range(5):
		draw_circle(Vector2(147 + index * 25, 268 + (index % 2) * 16), 59, Color(0.57, 0.68, 0.72, 0.025))
	draw_arc(Vector2(205, 282), 96, 0.3, 5.9, 60, Color(0.64, 0.74, 0.79, 0.17), 1.0, true)
	draw_string(ThemeDB.fallback_font, Vector2(142, 288), "FOG · VISUAL ONLY", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("718e9b"))
	for index in range(6):
		var point := Vector2(729 + index * 27, 506 + (index % 2) * 11)
		draw_line(point, point + Vector2(-9, 15), Color(0.53, 0.59, 0.77, 0.25), 1.0, true)
	draw_string(ThemeDB.fallback_font, Vector2(776, 550), "STORM · VISUAL ONLY", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("7d8da8"))
	# Orientation marks and sea chart boundary remain readable at a glance.
	draw_rect(SEA_RECT, Color("35505d"), false, 1.0)
	draw_string(ThemeDB.fallback_font, Vector2(42, 144), "SEARCH AREA 01", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, MUTED)
	draw_string(ThemeDB.fallback_font, Vector2(42, 552), "15 DISTRESS CONTACTS / ROCKY WATERS", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("6d8998"))
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
	_hud.add_child(top)
	var title := _label("ONE LAST LIGHT", 21, TEXT)
	title.position = Vector2(16, 5)
	top.add_child(title)
	_emergency_label = _label("", 15, TEAL)
	_emergency_label.position = Vector2(298, 9)
	top.add_child(_emergency_label)
	_round_label = _label("LEVEL 1", 14, MUTED)
	_round_label.position = Vector2(994, 9)
	top.add_child(_round_label)
	var captions: Array[String] = ["TIME", "ABOARD", "MAIN", "EMERGENCY", "DELIVERED", "LOST", "IN THE WATER", "STAR BANK"]
	for index in range(captions.size()):
		var column_x := 16 + index * 139
		var caption_text := captions[index]
		if caption_text in ["MAIN", "EMERGENCY"]:
			caption_text += " SAVES"
		var caption := _label(caption_text, 11, MUTED)
		caption.position = Vector2(column_x, 40)
		top.add_child(caption)
		var value := _label("0", 22, TEXT)
		value.position = Vector2(column_x, 55)
		top.add_child(value)
		_stat_labels[captions[index]] = value
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


func _refresh_hud() -> void:
	if _stat_labels.is_empty() or manager.emergency == null:
		return
	_stat_labels["ABOARD"].text = "%d/%d" % [boat.passengers.size(), boat.capacity]
	_stat_labels["ABOARD"].modulate = GOLD if boat.is_full() else TEAL
	_stat_labels["MAIN"].text = str(manager.main_delivered)
	_stat_labels["EMERGENCY"].text = str(manager.emergency_delivered)
	_stat_labels["DELIVERED"].text = str(manager.rescued_count)
	_stat_labels["LOST"].text = "%d/%d" % [manager.lost_count, manager.loss_limit]
	_stat_labels["IN THE WATER"].text = str(manager.active_count())
	_stat_labels["STAR BANK"].text = str(manager.stars)
	_stat_labels["STAR BANK"].modulate = GOLD
	var seconds := ceili(manager.time_remaining)
	_stat_labels["TIME"].text = "%d:%02d" % [floori(seconds / 60.0), seconds % 60]
	_stat_labels["TIME"].modulate = GOLD if seconds <= 30 else TEXT
	_emergency_label.text = "Emergency boat   %d/%d   ·   %s" % [emergency.passengers.size(), emergency.capacity, emergency.state_text()]
	if is_instance_valid(emergency.target):
		_emergency_label.text += "   #%02d" % emergency.target.survivor_id
	elif emergency.state == EmergencyBoat.State.COOLDOWN:
		_emergency_label.text += "   %ds" % ceili(emergency.cooldown_remaining)
	_context.text = manager.context_hint()
	_round_label.text = "LEVEL %d" % manager.round_index
	_refresh_shop()


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
	_notice_time = 0.0
	_notice_priority = 0
	_paused = false
	_tutorial_open = false
	get_tree().paused = false
	_clear_menu()


## The tutorial is pure UI. Until Launch Rescue, the manager keeps the clock, oxygen,
## both boats and the lighthouse stopped, and every gameplay input checks round_active.
func _show_tutorial() -> void:
	_tutorial_open = true
	_tutorial_step = 0
	_render_tutorial_step()


func _render_tutorial_step() -> void:
	var step: Dictionary = TUTORIAL_STEPS[_tutorial_step]
	_open_menu()
	var counter := _add_menu_label("Step %d of %d" % [_tutorial_step + 1, TUTORIAL_STEPS.size()], 14, TEAL)
	counter.name = "TutorialStepLabel"
	var icon := TutorialIcon.new(step["icon"])
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_menu_box.add_child(icon)
	var title := _add_menu_label(step["title"], 32, TEXT)
	title.name = "TutorialTitle"
	_menu_box.add_child(_tutorial_progress(_tutorial_step))
	_menu_box.add_child(_tutorial_body(step["lines"]))
	_menu_box.add_child(HSeparator.new())
	_menu_box.add_child(_tutorial_navigation(_tutorial_step))


func _tutorial_progress(current: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "TutorialProgress"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	for index in range(TUTORIAL_STEPS.size()):
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
	var is_last := step == TUTORIAL_STEPS.size() - 1
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
	_tutorial_step = clampi(step, 0, TUTORIAL_STEPS.size() - 1)
	_render_tutorial_step()


func _launch_first_round() -> void:
	# Only the open tutorial may launch, so a repeated press cannot start a second round.
	if not _tutorial_open or manager.round_active:
		return
	_tutorial_open = false
	_begin_level_intro()


func _show_results() -> void:
	_open_menu()
	match manager.result:
		RescueGameManager.Result.VICTORY:
			_add_menu_label("LEVEL 1 COMPLETE", 14, TEAL)
			_add_menu_label("Survivors brought to safety", 28, TEXT)
		RescueGameManager.Result.TOO_MANY_LOST:
			_add_menu_label("GAME OVER – Too Many Survivors Lost", 27, Color("fa958a"))
		RescueGameManager.Result.TIME_RAN_OUT:
			_add_menu_label("GAME OVER – Time Ran Out", 27, Color("fa958a"))
	_add_menu_label("%d of %d rescued   ·   %d lost   ·   %d still in the water   ·   %d aboard" % [manager.rescued_count, survivors.size(), manager.lost_count, manager.active_count(), boat.passengers.size() + emergency.passengers.size()], 16, TEXT)
	_add_menu_label("Main boat   %d     /     Emergency boat   %d" % [manager.main_delivered, manager.emergency_delivered], 15, MUTED)
	_menu_box.add_child(HSeparator.new())
	_bank_label = _add_menu_label("", 20, GOLD)
	_speed_button = _button("", _buy_speed)
	_menu_box.add_child(_speed_button)
	_purchase_feedback = _add_menu_label("Purchased speed carries into your next launch.", 13, MUTED)
	var retry := _button("REPLAY LEVEL 1", _retry_round)
	_menu_box.add_child(retry)
	_refresh_shop()
	retry.grab_focus()


func _refresh_shop() -> void:
	if not is_instance_valid(_speed_button):
		return
	_bank_label.text = "%d STARS AVAILABLE" % manager.stars
	var speed_maxed := manager.speed_level >= manager.economy.maximum_upgrade_level
	var bonus := roundi(manager.speed_level * boat.speed_bonus_per_level * 100)
	if speed_maxed:
		_speed_button.text = "MAIN BOAT SPEED   +%d%%   /   MAXIMUM REACHED" % bonus
	else:
		var next_bonus := roundi((manager.speed_level + 1) * boat.speed_bonus_per_level * 100)
		_speed_button.text = "MAIN BOAT SPEED   +%d%% → +%d%%    /    %d stars" % [bonus, next_bonus, manager.speed_cost()]
	_speed_button.disabled = speed_maxed or manager.stars < manager.speed_cost()


func _buy_speed() -> void:
	if manager.buy_speed_upgrade():
		_purchase_feedback.text = "Upgrade purchased. Main boat speed is now %d px/s." % roundi(boat.base_speed * boat.speed_multiplier)


func _retry_round() -> void:
	_begin_level_intro()


func _toggle_pause() -> void:
	_paused = not _paused
	get_tree().paused = _paused
	if _paused:
		_open_menu()
		_add_menu_label("OPERATIONS PAUSED", 12, TEAL)
		_add_menu_label("Take a bearing", 32, TEXT)
		_add_menu_label("The level clock, oxygen, lighthouse and both boats are paused.", 16, MUTED)
		var resume := _button("RESUME RESCUE", _toggle_pause)
		_menu_box.add_child(resume)
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
	manager.prepare_round()
	_intro_elapsed = 0.0
	_go_remaining = 0.0
	_intro_active = true
	_apply_arrival(0.0)
	_update_countdown_display()


func _advance_intro(delta: float) -> void:
	if _intro_active:
		_intro_elapsed = minf(_intro_elapsed + delta, INTRO_DURATION)
		if _intro_elapsed < INTRO_DURATION:
			_apply_arrival(delta)
			_update_countdown_display()
		else:
			_finish_intro()
	elif _go_remaining > 0.0:
		_go_remaining = maxf(_go_remaining - delta, 0.0)
		_update_go_display()


func _finish_intro() -> void:
	_intro_active = false
	# Land exactly on the berth with the normal start heading, so activation causes no jump.
	boat.global_position = manager.boat_spawn
	boat.heading = PI
	boat.velocity = Vector2.ZERO
	boat.queue_redraw()
	manager.begin_round()
	_go_remaining = GO_DURATION
	_update_go_display()


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


func _open_menu() -> void:
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
	panel.custom_minimum_size.x = 660
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
	_purchase_feedback = null
	_speed_button = null
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
			3: # Emergency call: pulse rings around a dispatch point.
				draw_circle(c, 5.0, GOLD_TONE)
				draw_arc(c, 13.0, 0.0, TAU, 28, Color(GOLD_TONE, 0.7), 2.0, true)
				draw_arc(c, 21.0, 0.0, TAU, 36, Color(GOLD_TONE, 0.35), 2.0, true)
