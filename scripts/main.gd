extends Node2D
## Assembles presentation; gameplay state belongs to GameManager and scene actors.

const SEA_RECT := Rect2(24, 116, 1104, 452)
const INK := Color("0d1c29")
const PANEL := Color("142937")
const TEXT := Color("e4ece8")
const MUTED := Color("91abb7")
const TEAL := Color("7fe0cc")
const GOLD := Color("ffda92")
## The HUD readouts that are plain numbers, left to right: caption and the widest value it will show.
## The survivor hearts sit between ABOARD and DELIVERED. The gaps between all six blocks are equal,
## so the bar looks balanced whether the level has one heart or six.
const HUD_COLUMNS := [["TIME", "4:00"], ["ABOARD", "4/4"], ["DELIVERED", "6/6"], ["LOST", "0"], ["STAR BANK", "000"]]
const HUD_LEFT := 16.0
const HUD_RIGHT := 1100.0
const HEARTS_CAPTION_WIDTH := 104.0
const HEART_SIZE := 26.0
const HEART_PITCH := 44.0
const HEARTS_TOP := 55.0
const NUMBER_WORDS := ["ZERO", "ONE", "TWO", "THREE", "FOUR", "FIVE", "SIX", "SEVEN", "EIGHT", "NINE", "TEN"]
const TUTORIAL_BODY_HEIGHT := 196.0
const TUTORIAL_BUTTON_WIDTH := 170.0
const ARROW_SVG := '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 16 16"><path d="M2 8h11M9 3.5 13.5 8 9 12.5" fill="none" stroke="white" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>'
## Level-start intro: a three-second countdown while the main boat sails in from above the chart.
const INTRO_DURATION := 3.0
const GO_DURATION := 0.7
const COUNTDOWN_CENTER := Vector2(576, 226)
const ARRIVAL_START_Y := SEA_RECT.position.y - 76.0

@onready var manager: RescueGameManager = $GameManager
@onready var boat: RescueBoat = $World/PlayerBoat
@onready var lighthouse: Lighthouse = $World/Lighthouse
@onready var harbor: Harbor = $World/Harbor

var _hud: CanvasLayer
var _stat_labels: Dictionary = {}
var _stat_captions: Dictionary = {}
var _context: Label
var _notice: Label
var _round_label: Label
var _menu: Control
var _menu_box: VBoxContainer
var _hearts: Array[SurvivorHeart] = []
var _hearts_caption: Label
var _hearts_row: Control
var _cue: MouseCue
var _bank_label: Label
var _offer_feedback: Label
var _offer_widgets: Dictionary = {}
var _continue_button: Button
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
	_build_hud()
	_build_countdown()
	_build_cue()
	manager.notification.connect(_on_notification)
	manager.state_changed.connect(_on_state_changed)
	manager.level_loaded.connect(_on_level_loaded)
	manager.round_started.connect(_on_round_started)
	manager.round_ended.connect(_show_results)
	manager.configure(boat, lighthouse, harbor, $World/Survivors)
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
	draw_string(ThemeDB.fallback_font, Vector2(42, 144), "SEARCH AREA %02d  ·  %s" % [manager.level_number, _level_title()], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, MUTED)
	draw_string(ThemeDB.fallback_font, Vector2(42, 552), "%d DISTRESS CONTACT%s / ROCKY WATERS" % [manager.survivors_total, "" if manager.survivors_total == 1 else "S"], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("6d8998"))
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
	_round_label = _label("LEVEL 1", 14, MUTED)
	_round_label.position = Vector2(994, 9)
	top.add_child(_round_label)
	for column in HUD_COLUMNS:
		var caption := _label(column[0], 11, MUTED)
		caption.position = Vector2(HUD_LEFT, 40)
		top.add_child(caption)
		_stat_captions[column[0]] = caption
		var value := _label("0", 22, TEXT)
		value.position = Vector2(HUD_LEFT, 55)
		top.add_child(value)
		_stat_labels[column[0]] = value
	_build_hearts_container(top)
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


func _build_hearts_container(top: Control) -> void:
	_hearts_caption = _label("SURVIVOR HEARTS", 11, MUTED)
	_hearts_caption.name = "HeartsCaption"
	_hearts_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hearts_caption.size = Vector2(HEARTS_CAPTION_WIDTH, 16)
	top.add_child(_hearts_caption)
	_hearts_row = Control.new()
	_hearts_row.name = "SurvivorHearts"
	_hearts_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(_hearts_row)


## One heart per survivor of the current level, in survivor_id order. Each heart reads its own
## Survivor, so the row never reorders, and a heart is never added or removed when a survivor
## changes state. Rebuilt from scratch whenever a level is loaded, then the bar is re-spaced.
func _rebuild_hearts() -> void:
	for heart in _hearts:
		if is_instance_valid(heart):
			_hearts_row.remove_child(heart) # Out of the tree now, so counts never see a stale heart.
			heart.queue_free()
	_hearts.clear()
	var ordered: Array[Survivor] = manager.survivors.duplicate()
	ordered.sort_custom(func(a: Survivor, b: Survivor) -> bool: return a.survivor_id < b.survivor_id)
	for index in range(ordered.size()):
		var heart := SurvivorHeart.new()
		heart.name = "Heart%02d" % ordered[index].survivor_id
		heart.size = Vector2(HEART_SIZE, HEART_SIZE)
		heart.position = Vector2(index * HEART_PITCH, 0)
		_hearts_row.add_child(heart)
		heart.bind(ordered[index])
		_hearts.append(heart)
	_layout_hud()


## Spaces TIME, ABOARD, the hearts, DELIVERED, LOST and STAR BANK with equal gaps between them.
func _layout_hud() -> void:
	var count := _hearts.size()
	var row_width := (count - 1) * HEART_PITCH + HEART_SIZE if count > 0 else 0.0
	var hearts_width := maxf(row_width, HEARTS_CAPTION_WIDTH)
	var blocks: Array = []
	for column in HUD_COLUMNS:
		var widest: float = maxf(_stat_captions[column[0]].get_minimum_size().x, ThemeDB.fallback_font.get_string_size(column[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x)
		blocks.append([column[0], widest])
		if column[0] == "ABOARD":
			blocks.append(["HEARTS", hearts_width])
	var total := 0.0
	for block in blocks:
		total += block[1]
	var gap := (HUD_RIGHT - HUD_LEFT - total) / (blocks.size() - 1)
	var x := HUD_LEFT
	for block in blocks:
		if block[0] == "HEARTS":
			_hearts_caption.size = Vector2(HEARTS_CAPTION_WIDTH, 16) # A label never shrinks by itself once it was larger.
			_hearts_caption.position = Vector2(x + (hearts_width - HEARTS_CAPTION_WIDTH) * 0.5, 40)
			_hearts_row.position = Vector2(x + (hearts_width - row_width) * 0.5, HEARTS_TOP)
		else:
			_stat_captions[block[0]].position.x = x
			_stat_labels[block[0]].position.x = x
		x += block[1] + gap


func _level_title() -> String:
	return manager.level.title.to_upper() if manager.level != null else ""


func _on_level_loaded(_level: LevelDefinition) -> void:
	_rebuild_hearts()
	_round_label.text = "LEVEL %d / %d" % [manager.level_number, manager.levels.size()]
	queue_redraw()


func _on_state_changed() -> void:
	_refresh_hud()
	_refresh_offer_ui()


func _refresh_hud() -> void:
	if _stat_labels.is_empty() or manager.level == null:
		return
	_stat_labels["ABOARD"].text = "%d/%d" % [boat.passengers.size(), boat.capacity]
	_stat_labels["ABOARD"].modulate = GOLD if boat.is_full() else TEAL
	_stat_labels["DELIVERED"].text = "%d/%d" % [manager.delivered_count, manager.survivors_total]
	_stat_labels["LOST"].text = str(manager.lost_count)
	_stat_labels["LOST"].modulate = Color("fa958a") if manager.lost_count > 0 else TEXT
	_stat_labels["STAR BANK"].text = str(manager.stars)
	_stat_labels["STAR BANK"].modulate = GOLD
	var seconds := ceili(manager.time_remaining)
	_stat_labels["TIME"].text = "%d:%02d" % [floori(seconds / 60.0), seconds % 60]
	_stat_labels["TIME"].modulate = GOLD if seconds <= 30 else TEXT
	_context.text = manager.context_hint()
	_round_label.text = "LEVEL %d / %d" % [manager.level_number, manager.levels.size()]


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
		_cue.play()
	_notice_time = 0.0
	_notice_priority = 0
	_paused = false
	_tutorial_open = false
	get_tree().paused = false
	_clear_menu()


## Pre-launch tutorial content, one page per step; "icon" selects a TutorialIcon drawing. The numbers
## come from the live level data and economy, so the text can never disagree with the game.
func _tutorial_content() -> Array:
	var level_count := manager.levels.size()
	var minutes := roundi(manager.levels[0].time_limit / 60.0)
	var seats := manager.economy.starting_capacity
	var stars := manager.economy.stars_per_survivor
	return [
		{
			"title": "Your Mission",
			"icon": 0,
			"lines": [
				"Rescue every survivor across %d levels, one level at a time." % level_count,
				"Deliver them all to the harbor before the %d-minute timer runs out." % minutes,
				"If a survivor runs out of oxygen, the level fails. You can replay it right away.",
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
				"Your boat starts with room for %d survivor%s. Return to the harbor and press E to deliver." % [seats, "" if seats == 1 else "s"],
			],
		},
		{
			"title": "Earn Stars & Upgrade",
			"icon": 3,
			"lines": [
				"Each survivor you deliver earns %d stars." % stars,
				"Between levels, spend stars to carry more survivors or sail faster. Upgrades stay for the whole campaign.",
				"Press Esc to pause or resume the game.",
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
	_open_menu()
	var counter := _add_menu_label("Step %d of %d" % [_tutorial_step + 1, _tutorial_content().size()], 14, TEAL)
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
	_begin_level_intro()


## --- Level results and campaign screens -------------------------------------------------------
## The manager decides what happened; these screens only show it and forward the player's choice.
func _show_results() -> void:
	_cue.stop()
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
	var earned := _add_menu_label("You earned %s!" % _stars_text(manager.level_stars), 30, GOLD)
	earned.name = "StarsEarned"
	_add_menu_label("%d of %d %s delivered   ·   %d lost" % [manager.delivered_count, manager.survivors_total, "survivor" if manager.survivors_total == 1 else "survivors", manager.lost_count], 16, TEXT)
	_bank_label = _add_menu_label("", 18, GOLD)
	_bank_label.name = "BankLabel"
	_menu_box.add_child(HSeparator.new())
	var next_number := level.level_number + 1
	if level.offer_screen == LevelDefinition.OfferScreen.POPUP and not level.upgrade_offers.is_empty():
		_add_offer_popup(level.upgrade_offers[0])
		_continue_button = _button("NOT NOW", _continue_campaign)
		_continue_button.name = "ContinueButton"
	elif level.offer_screen == LevelDefinition.OfferScreen.PREPARE:
		_continue_button = _button("CONTINUE", _show_prepare)
		_continue_button.name = "ContinueButton"
	else:
		_continue_button = _button("CONTINUE TO LEVEL %d" % next_number, _continue_campaign)
		_continue_button.name = "ContinueButton"
	_menu_box.add_child(_continue_button)
	_refresh_offer_ui()
	_continue_button.grab_focus()


## The single-offer panel shown on the level-complete screen.
func _add_offer_popup(offer: UpgradeOffer) -> void:
	var question := _add_menu_label("", 17, TEXT)
	question.name = "OfferQuestion_%s" % offer.id
	question.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var button := _button("", _on_offer_pressed.bind(offer.id))
	button.name = "OfferButton_%s" % offer.id
	_menu_box.add_child(button)
	_offer_feedback = _add_menu_label("", 13, MUTED)
	_offer_feedback.name = "OfferFeedback"
	_offer_widgets[offer.id] = {"button": button, "question": question, "card": null}


## The "prepare for the next level" screen: pick one of the offers or keep the stars.
func _show_prepare() -> void:
	var level := manager.level
	var next_number := level.level_number + 1
	var next_count: int = manager.levels[mini(manager.level_index + 1, manager.levels.size() - 1)].survivors.size()
	_open_menu()
	var heading := _add_menu_label("PREPARE FOR LEVEL %d" % next_number, 14, TEAL)
	heading.name = "ResultHeading"
	var subtitle := _add_menu_label("%s survivors are waiting. Choose your next boat upgrade." % NUMBER_WORDS[mini(next_count, NUMBER_WORDS.size() - 1)].capitalize(), 22, TEXT)
	subtitle.name = "PrepareSubtitle"
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bank_label = _add_menu_label("", 18, GOLD)
	_bank_label.name = "BankLabel"
	var cards := HBoxContainer.new()
	cards.name = "OfferCards"
	cards.add_theme_constant_override("separation", 14)
	_menu_box.add_child(cards)
	for offer in level.upgrade_offers:
		cards.add_child(_offer_card(offer))
	_offer_feedback = _add_menu_label("", 13, MUTED)
	_offer_feedback.name = "OfferFeedback"
	_continue_button = _button("KEEP MY STARS", _continue_campaign)
	_continue_button.name = "ContinueButton"
	_menu_box.add_child(_continue_button)
	_refresh_offer_ui()
	_continue_button.grab_focus()


func _offer_card(offer: UpgradeOffer) -> PanelContainer:
	var card := PanelContainer.new()
	card.name = "OfferCard_%s" % offer.id
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", _style(Color("173340"), Color("41616b"), 8))
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	card.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)
	var title := _label("", 15, TEAL)
	title.name = "Title"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var detail := _label("", 19, TEXT)
	detail.name = "Detail"
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.custom_minimum_size.y = 64
	box.add_child(detail)
	var button := _button("", _on_offer_pressed.bind(offer.id))
	button.name = "OfferButton_%s" % offer.id
	box.add_child(button)
	_offer_widgets[offer.id] = {"button": button, "title": title, "detail": detail, "card": card}
	return card


func _on_offer_pressed(offer_id: StringName) -> void:
	# The manager is the single authority: a second press, a locked offer or too few stars is refused.
	if manager.purchase_offer(offer_id):
		var offer := manager.level.offer_by_id(offer_id)
		if offer.kind == UpgradeOffer.Kind.CAPACITY:
			_offer_feedback.text = "Upgrade purchased. Your boat now carries %d passengers." % manager.economy.capacity
		else:
			_offer_feedback.text = "Upgrade purchased. Boat speed is now %d px/s." % roundi(boat.base_speed * boat.speed_multiplier)
		_offer_feedback.add_theme_color_override("font_color", TEAL)
	_refresh_offer_ui()


## Keeps every price, value and button state equal to the real economy.
func _refresh_offer_ui() -> void:
	if not is_instance_valid(_bank_label) or manager.level == null:
		return
	_bank_label.text = "STAR BANK: %s" % _stars_text(manager.economy.stars)
	var purchased := false
	for offer in manager.level.upgrade_offers:
		if manager.economy.is_claimed(offer):
			purchased = true
	for offer in manager.level.upgrade_offers:
		if not _offer_widgets.has(offer.id):
			continue
		var widgets: Dictionary = _offer_widgets[offer.id]
		var button: Button = widgets["button"]
		if not is_instance_valid(button):
			continue
		var quote := manager.economy.preview(offer)
		if quote["reason"] == "claimed":
			# A bought offer keeps showing what it bought, not what a further step would cost.
			quote["after"] = quote["before"]
			quote["before"] = maxi(quote["before"] - offer.amount, 0)
		var locked := manager.is_offer_locked(offer)
		var capacity := offer.kind == UpgradeOffer.Kind.CAPACITY
		if widgets.has("question") and is_instance_valid(widgets["question"]):
			widgets["question"].text = "Upgrade your boat capacity from %d to %d passengers?" % [quote["before"], quote["after"]] if capacity \
				else "Raise your boat speed from +%d%% to +%d%%?" % [_speed_bonus(quote["before"]), _speed_bonus(quote["after"])]
		if widgets.has("title") and is_instance_valid(widgets["title"]):
			widgets["title"].text = "BOAT CAPACITY" if capacity else "BOAT SPEED"
			widgets["detail"].text = ("%d to %d passengers" % [quote["before"], quote["after"]]) if capacity \
				else "+%d%% to +%d%%\n%d px/s to %d px/s" % [_speed_bonus(quote["before"]), _speed_bonus(quote["after"]), _speed_pixels(quote["before"]), _speed_pixels(quote["after"])]
		match quote["reason"]:
			"claimed": button.text = "PURCHASED"
			"maximum": button.text = "MAXIMUM REACHED"
			_: button.text = "LOCKED" if locked else "UPGRADE — %s" % _stars_text(offer.cost).to_upper()
		button.disabled = locked or not quote["available"]
		if not quote["available"] and quote["reason"] == "stars" and not locked and not purchased and is_instance_valid(_offer_feedback):
			_offer_feedback.text = "Not enough stars. You need %d more." % (offer.cost - manager.economy.stars)
			_offer_feedback.add_theme_color_override("font_color", MUTED)
	if is_instance_valid(_continue_button):
		if purchased:
			if manager.level.offer_screen == LevelDefinition.OfferScreen.POPUP:
				_continue_button.text = "CONTINUE TO LEVEL %d" % (manager.level_number + 1)
			elif manager.level.offer_screen == LevelDefinition.OfferScreen.PREPARE:
				_continue_button.text = "START LEVEL %d" % (manager.level_number + 1)


func _speed_bonus(level: int) -> int:
	return roundi(level * boat.speed_bonus_per_level * 100.0)


func _speed_pixels(level: int) -> int:
	return roundi(boat.base_speed * (1.0 + level * boat.speed_bonus_per_level))


func _show_failure() -> void:
	_open_menu()
	var heading := _add_menu_label("LEVEL %d FAILED" % manager.level_number, 14, Color("fa958a"))
	heading.name = "ResultHeading"
	var reason := ""
	if manager.result == RescueGameManager.Result.TIME_RAN_OUT:
		reason = "Time ran out"
	else:
		reason = "Survivor %02d was lost" % manager.lost_ids[0] if not manager.lost_ids.is_empty() else "A survivor was lost"
	var why := _add_menu_label(reason, 28, Color("fa958a"))
	why.name = "FailureReason"
	_add_menu_label("%d of %d delivered   ·   %d lost   ·   %d still in the water   ·   %d aboard" % [manager.delivered_count, manager.survivors_total, manager.lost_count, manager.active_count(), boat.passengers.size()], 16, TEXT)
	_bank_label = _add_menu_label("", 18, GOLD)
	_bank_label.name = "BankLabel"
	_bank_label.text = "STAR BANK: %s  ·  upgrades are kept" % _stars_text(manager.economy.stars)
	_menu_box.add_child(HSeparator.new())
	var retry := _button("REPLAY LEVEL %d" % manager.level_number, _retry_round)
	retry.name = "ReplayButton"
	_menu_box.add_child(retry)
	retry.grab_focus()


func _show_campaign_complete() -> void:
	var economy := manager.economy
	_open_menu()
	var heading := _add_menu_label("ALL %s LEVELS COMPLETE" % NUMBER_WORDS[mini(manager.levels.size(), NUMBER_WORDS.size() - 1)], 24, GOLD)
	heading.name = "ResultHeading"
	var message := _add_menu_label("Every survivor made it home. The light stayed on.", 17, TEXT)
	message.name = "VictoryMessage"
	var stats := _add_menu_label("Survivors rescued: %d     Stars earned: %d     Star bank: %d" % [economy.total_rescued, economy.total_stars_earned, economy.stars], 16, TEAL)
	stats.name = "CampaignStats"
	var upgrades := _add_menu_label(_upgrade_summary(), 14, MUTED)
	upgrades.name = "UpgradeSummary"
	upgrades.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_menu_box.add_child(HSeparator.new())
	var restart := _button("RESTART CAMPAIGN", _restart_campaign)
	restart.name = "RestartButton"
	_menu_box.add_child(restart)
	restart.grab_focus()


func _upgrade_summary() -> String:
	var economy := manager.economy
	if economy.purchases.is_empty():
		return "Upgrades purchased: none"
	var parts: Array[String] = []
	for purchase in economy.purchases:
		parts.append("%s (level %d, %s)" % ["capacity +1" if purchase["kind"] == UpgradeOffer.Kind.CAPACITY else "speed +%d%%" % roundi(boat.speed_bonus_per_level * 100), purchase["level"], _stars_text(purchase["cost"])])
	return "Upgrades purchased: " + ", ".join(parts) + ".   Final boat: %d passengers, %d px/s." % [economy.capacity, roundi(boat.base_speed * boat.speed_multiplier)]


## Forward from a won level. The manager refuses a second call, so a double click cannot skip a level.
func _continue_campaign() -> void:
	if _intro_active:
		return
	if manager.advance_level():
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
	_offer_feedback = null
	_offer_widgets.clear()
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
