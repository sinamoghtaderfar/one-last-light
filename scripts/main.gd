extends Node2D
## Assembles presentation; gameplay state belongs to GameManager and scene actors.

const SEA_RECT := Rect2(24, 116, 1104, 452)
const INK := Color("0d1c29")
const PANEL := Color("142937")
const TEXT := Color("e4ece8")
const MUTED := Color("91abb7")
const TEAL := Color("7fe0cc")
const GOLD := Color("ffda92")

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


func _ready() -> void:
	for node in $World/Survivors.get_children():
		if node is Survivor:
			survivors.append(node)
	_build_hud()
	manager.notification.connect(_on_notification)
	manager.state_changed.connect(_refresh_hud)
	manager.round_started.connect(_on_round_started)
	manager.round_ended.connect(_show_results)
	manager.configure(boat, lighthouse, harbor, survivors, emergency)
	_show_intro()
	queue_redraw()


func _process(delta: float) -> void:
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
	get_tree().paused = false
	_clear_menu()


func _show_intro() -> void:
	_open_menu()
	_add_menu_label("LEVEL 1    /    ROCKY WATERS", 13, TEAL)
	_add_menu_label("One Last Light", 36, TEXT)
	_add_menu_label("Find all 15 survivors. Deliver every living passenger within four minutes.\nYou can lose up to two people. A third loss ends the rescue.", 18, TEXT)
	_menu_box.add_child(HSeparator.new())
	_add_menu_label("Aim the lighthouse with your mouse to read oxygen times.\nContacts fade after three seconds. Press E within pickup range, even in darkness.", 15, MUTED)
	_add_menu_label("Steer with WASD or arrows. Press E near a survivor to pick them up.\nYour boat seats two. Press E at the harbor to earn %d stars per person." % manager.stars_per_survivor, 15, TEXT)
	_add_menu_label("Right-click a visible survivor to dispatch the one-seat emergency boat.\nIt returns on its own and saves a life for zero stars.", 15, TEXT)
	var launch := _button("LAUNCH RESCUE", _launch_first_round)
	_menu_box.add_child(launch)
	launch.grab_focus()


func _launch_first_round() -> void:
	manager.start_round()


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
	manager.restart_round()


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
