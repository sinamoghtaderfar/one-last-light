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
var _capacity_button: Button
var _speed_button: Button
var _bank_label: Label
var _notice_time: float = 0.0
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
	manager.configure(boat, lighthouse, harbor, survivors)
	_show_intro()
	queue_redraw()


func _process(delta: float) -> void:
	_refresh_hud()
	harbor.set_boat_present(harbor.contains_point(boat.global_position))
	if not _paused and manager.round_active:
		_notice_time = maxf(_notice_time - delta, 0.0)
		if _notice_time == 0.0:
			_notice.text = "Rescue priority: oxygen remaining · travel distance · open seats"
			_notice.modulate = MUTED


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause_game") and manager.round_active:
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
	draw_string(ThemeDB.fallback_font, Vector2(42, 552), "10 DISTRESS CONTACTS / ROCKY WATERS", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("6d8998"))
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
	_round_label = _label("GRAYBOX 0.1  /  RESCUE 01", 11, MUTED)
	_round_label.position = Vector2(768, 12)
	_round_label.size.x = 334
	_round_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	top.add_child(_round_label)
	var captions: Array[String] = ["ABOARD", "DELIVERED", "LOST", "IN THE WATER", "STAR BANK", "ELAPSED"]
	for index in range(captions.size()):
		var card := HBoxContainer.new()
		card.position = Vector2(16 + index * 184, 46)
		card.size = Vector2(170, 34)
		card.add_theme_constant_override("separation", 12)
		top.add_child(card)
		var value := _label("0", 24, TEAL if index < 2 else TEXT)
		value.custom_minimum_size.x = 48
		card.add_child(value)
		var caption := _label(captions[index], 10, MUTED)
		caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		card.add_child(caption)
		_stat_labels[captions[index]] = value
	var bottom := _panel_at(Rect2(16, 580, 1120, 56), PANEL)
	_hud.add_child(bottom)
	_context = _label("", 15, TEXT)
	_context.position = Vector2(16, 6)
	_context.size.x = 1080
	bottom.add_child(_context)
	_notice = _label("", 12, MUTED)
	_notice.position = Vector2(16, 31)
	_notice.size.x = 1080
	bottom.add_child(_notice)


func _refresh_hud() -> void:
	if _stat_labels.is_empty():
		return
	_stat_labels["ABOARD"].text = "%d/%d" % [boat.passengers.size(), boat.capacity]
	_stat_labels["ABOARD"].modulate = GOLD if boat.is_full() else TEAL
	_stat_labels["DELIVERED"].text = str(manager.rescued_count)
	_stat_labels["LOST"].text = str(manager.lost_count)
	_stat_labels["IN THE WATER"].text = str(manager.active_count())
	_stat_labels["STAR BANK"].text = str(manager.stars)
	_stat_labels["STAR BANK"].modulate = GOLD
	_stat_labels["ELAPSED"].text = "%02d:%02d" % [floori(manager.elapsed_time / 60.0), int(manager.elapsed_time) % 60]
	_context.text = manager.context_hint()
	_round_label.text = "GRAYBOX 0.1  /  RESCUE %02d  /  %d MARKED" % [manager.round_index, manager.discovered_count()]
	_refresh_shop()


func _on_notification(message: String, tone: String) -> void:
	_notice.text = message
	_notice_time = 5.0
	match tone:
		"success": _notice.modulate = TEAL
		"warning": _notice.modulate = GOLD
		"danger": _notice.modulate = Color("fa958a")
		_: _notice.modulate = MUTED


func _on_round_started() -> void:
	_paused = false
	get_tree().paused = false
	_clear_menu()


func _show_intro() -> void:
	_open_menu()
	_add_menu_label("RESCUE OPERATIONS / 01", 12, TEAL)
	_add_menu_label("One Last Light", 36, TEXT)
	_add_menu_label("Ten lives in the water. Three seats aboard.\nEvery journey back is a decision.", 18, MUTED)
	_menu_box.add_child(HSeparator.new())
	_add_menu_label("DETECT → PRIORITIZE → RESCUE → RETURN → UPGRADE", 12, GOLD)
	_add_menu_label("The lighthouse sweeps the sea automatically. Illuminated survivors\nstay marked, with their oxygen time visible beside them.\n\nSteer close and press E to bring a survivor aboard. Their oxygen\nstops, but stars are earned only after delivery at the right-hand harbor.", 15, TEXT)
	_add_menu_label("WASD / ARROWS   Move     E   Pick up / unload     ESC   Pause", 13, MUTED)
	var launch := _button("LAUNCH RESCUE", _launch_first_round)
	_menu_box.add_child(launch)
	_add_menu_label("Game Production and Management · WS 2026/27 · Prototype 0.1", 10, MUTED)
	launch.grab_focus()


func _launch_first_round() -> void:
	manager.start_round()


func _show_results() -> void:
	_open_menu()
	_add_menu_label("RESCUE %02d / DEBRIEF" % manager.round_index, 12, TEAL)
	var heading := "Every light brought home" if manager.rescued_count == survivors.size() else "The search is over"
	_add_menu_label(heading, 30, TEXT)
	_add_menu_label("%d / %d delivered   ·   %d lost   ·   %02d:%02d elapsed" % [manager.rescued_count, survivors.size(), manager.lost_count, floori(manager.elapsed_time / 60.0), int(manager.elapsed_time) % 60], 17, MUTED)
	_bank_label = _add_menu_label("", 22, GOLD)
	_add_menu_label("Spend your stars before launching another round.", 14, MUTED)
	_capacity_button = _button("", _buy_capacity)
	_menu_box.add_child(_capacity_button)
	_speed_button = _button("", _buy_speed)
	_menu_box.add_child(_speed_button)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	_menu_box.add_child(actions)
	var retry := _button("RETRY ROUND", _retry_round)
	retry.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(retry)
	var next := _button("NEXT ROUND →", _next_round)
	next.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(next)
	_add_menu_label("The same sea, a better boat. Banked stars and upgrades carry over.\nNo survivors remain aboard; every rescue counted here reached safety.", 12, MUTED)
	_refresh_shop()
	next.grab_focus()


func _refresh_shop() -> void:
	if not is_instance_valid(_capacity_button):
		return
	_bank_label.text = "%d STARS AVAILABLE" % manager.stars
	var capacity_maxed: bool = manager.capacity_level >= manager.maximum_upgrade_level
	var speed_maxed: bool = manager.speed_level >= manager.maximum_upgrade_level
	_capacity_button.text = "CAPACITY  %d → %d seats    /    %d stars" % [boat.capacity, boat.capacity + 1, manager.capacity_cost()] if not capacity_maxed else "CAPACITY  %d seats    /    MAXIMUM REACHED" % boat.capacity
	_speed_button.text = "SPEED  +%d%% → +%d%%    /    %d stars" % [roundi(manager.speed_level * boat.speed_bonus_per_level * 100), roundi((manager.speed_level + 1) * boat.speed_bonus_per_level * 100), manager.speed_cost()] if not speed_maxed else "SPEED  +%d%%    /    MAXIMUM REACHED" % roundi(manager.speed_level * boat.speed_bonus_per_level * 100)
	_capacity_button.disabled = capacity_maxed or manager.stars < manager.capacity_cost()
	_speed_button.disabled = speed_maxed or manager.stars < manager.speed_cost()


func _buy_capacity() -> void:
	manager.buy_capacity_upgrade()


func _buy_speed() -> void:
	manager.buy_speed_upgrade()


func _retry_round() -> void:
	manager.restart_round()


func _next_round() -> void:
	manager.next_round()


func _toggle_pause() -> void:
	_paused = not _paused
	get_tree().paused = _paused
	if _paused:
		_open_menu()
		_add_menu_label("OPERATIONS PAUSED", 12, TEAL)
		_add_menu_label("Take a bearing", 32, TEXT)
		_add_menu_label("Oxygen, boat movement, and the lighthouse are paused.\nReturn passengers to the safe zone on the right and press E.\nOnly delivered survivors earn stars.", 16, MUTED)
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
	_capacity_button = null
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
