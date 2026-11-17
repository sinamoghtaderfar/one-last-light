extends SceneTree
## godot --headless --fixed-fps 60 --path . --script res://tests/hud_suite.gd
## Covers the simplified top HUD and the fifteen survivor hearts: what was removed, layout fit,
## binding to Survivor objects, draining fill and colours, the critical-only pulse, the aboard,
## delivered and lost states with their animations, replay reset, and freezing with the game.
## When run windowed (not --headless) it also samples real rendered pixels of the hearts.

const STEP := 1.0 / 60.0
const FORBIDDEN_HUD_TEXT := ["MAIN", "EMERGENCY", "IN THE WATER", "SAVES", "READY", "COOLDOWN"]
const REQUIRED_HUD_TEXT := ["ONE LAST LIGHT", "LEVEL 1", "TIME", "ABOARD", "SURVIVOR HEARTS", "DELIVERED", "LOST", "STAR BANK"]

var checks: int = 0
var failures: Array[String] = []
var main: Node
var manager: RescueGameManager
var boat: RescueBoat
var harbor: Harbor
var by_id: Dictionary = {}
var hearts: Array = []
var sections_started: int = 0
var sections_done: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("Display: %s" % DisplayServer.get_name())
	await _boot()
	if main == null:
		_finish()
		return
	await _check_removed_and_layout()
	await _check_binding_and_order()
	await _check_frozen_before_play()
	await _boot()
	_start_round()
	await _check_fill_and_colour()
	await _check_critical_pulse()
	await _boot()
	_start_round()
	await _check_aboard_and_delivered()
	await _boot()
	_start_round()
	await _check_lost_and_drain_live()
	await _boot()
	_start_round()
	await _check_replay_reset()
	await _boot()
	_start_round()
	await _check_pause_freezes_hearts()
	if DisplayServer.get_name() != "headless":
		await _boot()
		_start_round()
		await _check_rendered_pixels()
	_finish()


# --- helpers --------------------------------------------------------------------------------

## Fresh Main scene. Main and the hearts are stepped by hand unless a section awaits real frames.
func _boot() -> void:
	if is_instance_valid(main):
		main.queue_free()
		await process_frame
	main = null
	var scene := load("res://scenes/main.tscn") as PackedScene
	if scene == null:
		_expect(false, "Main scene loads")
		return
	main = scene.instantiate()
	root.add_child(main)
	await process_frame
	manager = main.get("manager") as RescueGameManager
	boat = main.get("boat") as RescueBoat
	harbor = main.get("harbor") as Harbor
	hearts = main.get("_hearts")
	by_id.clear()
	for person in manager.survivors:
		by_id[person.survivor_id] = person


## Leaves the tutorial and the countdown instantly and starts live play.
func _start_round() -> void:
	main.set_process(false)
	for step in range(3):
		main.call("_tutorial_next")
	main.call("_launch_first_round")
	main.call("_advance_intro", 10.0)
	for heart: SurvivorHeart in hearts:
		heart.set_process(false)
		heart.advance(0.0)


## Moves every heart forward by seconds of simulated frames.
func _tick(seconds: float) -> void:
	var remaining := seconds
	while remaining > 0.0:
		var dt := minf(STEP, remaining)
		for heart: SurvivorHeart in hearts:
			heart.advance(dt)
		remaining -= dt


func _heart(id: int) -> SurvivorHeart:
	return hearts[id - 1] as SurvivorHeart


func _top_panel() -> Control:
	return (main.get("_hud") as CanvasLayer).get_child(0) as Control


func _set_oxygen(id: int, seconds: float) -> void:
	by_id[id].oxygen_remaining = seconds
	_heart(id).advance(0.0)


func _color_gap(a: Color, b: Color) -> float:
	return maxf(maxf(absf(a.r - b.r), absf(a.g - b.g)), maxf(absf(a.b - b.b), absf(a.a - b.a)))


## All fifteen hearts still exist, are in the scene, share one row and are visible.
func _all_hearts_present() -> bool:
	if hearts.size() != 15:
		return false
	var row: Node = null
	for heart in hearts:
		if not is_instance_valid(heart) or not (heart as Node).is_inside_tree() or not (heart as CanvasItem).visible:
			return false
		row = row if row != null else (heart as Node).get_parent()
		if (heart as Node).get_parent() != row:
			return false
	return row.get_child_count() == 15


func _order() -> Array[int]:
	var ids: Array[int] = []
	for heart: SurvivorHeart in hearts:
		ids.append(heart.survivor.survivor_id)
	return ids


# --- sections -------------------------------------------------------------------------------

func _check_removed_and_layout() -> void:
	sections_started += 1
	var top := _top_panel()
	var texts: Array[String] = []
	for label: Label in top.find_children("*", "Label", true, false):
		texts.append(label.text.to_upper())
	var offending: Array[String] = []
	for text in texts:
		for fragment in FORBIDDEN_HUD_TEXT:
			if fragment in text:
				offending.append(text)
	_expect(offending.is_empty(), "No emergency status, MAIN SAVES, EMERGENCY SAVES or IN THE WATER text remains in the top HUD%s" % ("" if offending.is_empty() else ": " + str(offending)))
	var missing: Array[String] = []
	for needed in REQUIRED_HUD_TEXT:
		if not needed in texts:
			missing.append(needed)
	_expect(missing.is_empty(), "The top HUD keeps the title, Level 1, TIME, ABOARD, SURVIVOR HEARTS, DELIVERED, LOST and STAR BANK%s" % ("" if missing.is_empty() else " (missing " + str(missing) + ")"))
	var stats := main.get("_stat_labels") as Dictionary
	_expect(stats.keys().size() == 5 and stats.has("TIME") and stats.has("ABOARD") and stats.has("DELIVERED") and stats.has("LOST") and stats.has("STAR BANK"),
		"Only the five numeric readouts are tracked; the removed ones leave no HUD references behind")
	for removed in ["MAIN", "EMERGENCY", "IN THE WATER"]:
		_expect(not stats.has(removed), "No leftover %s label reference" % removed)
	_expect(main.get("_emergency_label") == null, "No leftover emergency status label reference")

	# Everything sits inside the panel, with no overlaps and no large dead gap.
	var panel_rect := Rect2(Vector2.ZERO, top.size)
	var inside := true
	for control: Control in top.find_children("*", "Control", true, false):
		var rect := Rect2(control.global_position - top.global_position, control.get_combined_minimum_size().max(control.size))
		inside = inside and panel_rect.grow(0.5).encloses(rect)
	_expect(inside, "Every HUD element fits inside the top panel")
	var row := top.find_child("SurvivorHearts", true, false) as Control
	var blocks: Array[Rect2] = []
	for caption in ["TIME", "ABOARD", "DELIVERED", "LOST", "STAR BANK"]:
		var value := stats[caption] as Label
		var title := _label_with_text(top, caption)
		var width := maxf(value.get_minimum_size().x, title.get_minimum_size().x)
		blocks.append(Rect2(title.position.x, 40.0, width, 40.0))
	var heart_extent := Rect2(row.position, Vector2(14 * 30.0 + 24.0, 24.0))
	blocks.append(Rect2(heart_extent.position.x, 40.0, heart_extent.size.x, 52.0))
	blocks.sort_custom(func(a: Rect2, b: Rect2) -> bool: return a.position.x < b.position.x)
	var overlap_free := true
	var widest_gap := 0.0
	for index in range(blocks.size() - 1):
		var gap := blocks[index + 1].position.x - blocks[index].end.x
		overlap_free = overlap_free and gap >= 12.0
		widest_gap = maxf(widest_gap, gap)
	_expect(overlap_free, "HUD columns and the heart row do not overlap or touch")
	_expect(widest_gap <= 150.0, "No large empty area: the widest gap between HUD blocks is %.0f px" % widest_gap)
	_expect(blocks[0].position.x <= 20.0 and top.size.x - blocks[-1].end.x <= 130.0, "The row of readouts spans the bar (right margin %.0f px)" % (top.size.x - blocks[-1].end.x))
	var title_label := _label_with_text(top, "ONE LAST LIGHT")
	var level_label := _label_with_text(top, "LEVEL 1")
	_expect(title_label.position.y + title_label.get_minimum_size().y <= 40.0 and level_label.position.y + level_label.get_minimum_size().y <= 40.0,
		"The title and Level 1 sit above the readouts without colliding")
	_expect(row.position.y + 24.0 + 12.0 <= top.size.y, "Hearts and their ID numbers stay inside the bar")
	sections_done += 1


func _label_with_text(parent: Node, text: String) -> Label:
	for label: Label in parent.find_children("*", "Label", true, false):
		if label.text == text:
			return label
	return null


func _check_binding_and_order() -> void:
	sections_started += 1
	_expect(hearts.size() == 15 and manager.survivors.size() == 15, "There are exactly 15 hearts for the 15 survivors")
	var ids := _order()
	var expected: Array[int] = []
	for id in range(1, 16):
		expected.append(id)
	_expect(ids == expected, "Hearts run in survivor_id order 1 to 15")
	var unique := {}
	var names_ok := true
	var bound_ok := true
	for heart: SurvivorHeart in hearts:
		unique[heart.survivor] = true
		names_ok = names_ok and heart.name == "Heart%02d" % heart.survivor.survivor_id
		bound_ok = bound_ok and by_id[heart.survivor.survivor_id] == heart.survivor
	_expect(unique.size() == 15 and names_ok and bound_ok, "Each heart is bound to a different one of the existing Survivor objects")
	var parent_ok := true
	for heart: SurvivorHeart in hearts:
		parent_ok = parent_ok and heart.get_parent() == hearts[0].get_parent()
	_expect(parent_ok and hearts[0].get_parent().get_child_count() == 15, "All hearts live in one row node")
	var pitch_ok := true
	for index in range(14):
		pitch_ok = pitch_ok and is_equal_approx(hearts[index + 1].position.x - hearts[index].position.x, 30.0) and hearts[index].position.y == hearts[0].position.y
	_expect(pitch_ok, "Hearts are evenly spaced on one line")
	sections_done += 1


func _check_frozen_before_play() -> void:
	sections_started += 1
	# Tutorial open: nothing is draining, nothing pulses, every heart is full.
	var full := true
	var calm := true
	for heart: SurvivorHeart in hearts:
		heart.advance(1.0)
		full = full and heart.shown_state == Survivor.State.ACTIVE and is_equal_approx(heart.fill_ratio, 1.0)
		calm = calm and not heart.is_pulsing() and is_equal_approx(heart.visual_scale(), 1.0)
	_expect(full, "While the tutorial is open all fifteen hearts are full and active")
	_expect(calm, "…and none of them pulses, even the survivors who start below the critical level")
	main.set_process(false)
	for step in range(3):
		main.call("_tutorial_next")
	main.call("_launch_first_round")
	var during_intro := true
	for step in range(40):
		main.call("_advance_intro", STEP)
		for heart: SurvivorHeart in hearts:
			heart.advance(STEP)
			during_intro = during_intro and not heart.is_pulsing() and is_equal_approx(heart.fill_ratio, 1.0) and heart.shown_state == Survivor.State.ACTIVE
	_expect(main.get("_intro_active") == true and during_intro, "During the level-start countdown the hearts stay full and still")
	main.call("_advance_intro", 10.0)
	_expect(_heart(6).is_pulsing(), "The moment play begins, the already-critical survivor's heart starts to pulse")
	sections_done += 1


func _check_fill_and_colour() -> void:
	sections_started += 1
	# Full oxygen: completely filled, in the comfortable colour, for every survivor with a long budget.
	var long_ok := true
	for heart: SurvivorHeart in hearts:
		var person := heart.survivor
		long_ok = long_ok and is_equal_approx(heart.fill_ratio, 1.0)
		if person.oxygen_duration > Survivor.WARNING_SECONDS + SurvivorHeart.BLEND_SECONDS:
			long_ok = long_ok and heart.fill_color() == SurvivorHeart.ACTIVE_COLOR
	_expect(long_ok, "At full oxygen every heart is completely filled, and green where the budget is comfortable")
	var short_ids: Array[int] = []
	for heart: SurvivorHeart in hearts:
		if heart.survivor.oxygen_duration <= Survivor.WARNING_SECONDS + SurvivorHeart.BLEND_SECONDS:
			short_ids.append(heart.survivor.survivor_id)
	_expect(short_ids == [1, 2, 4, 6, 10], "Only the five survivors whose whole budget is under about a minute start in warning colours (%s)" % str(short_ids))

	# The fill equals the true oxygen share, all the way down.
	var exact := true
	var monotonic := true
	var last := 2.0
	var person: Survivor = by_id[8]
	for step in range(0, 101):
		person.oxygen_remaining = person.oxygen_duration * (1.0 - step / 100.0)
		var heart := _heart(8)
		heart.advance(0.0)
		var ratio := clampf(person.oxygen_remaining / person.oxygen_duration, 0.0, 1.0)
		exact = exact and is_equal_approx(heart.fill_ratio, ratio)
		monotonic = monotonic and heart.fill_ratio <= last + 0.000001
		last = heart.fill_ratio
	_expect(exact, "The filled share of a heart is oxygen_remaining / oxygen_duration at every level from 100% to 0%")
	_expect(monotonic and is_zero_approx(_heart(8).fill_ratio), "Fill only ever decreases as oxygen runs out, ending hollow")
	person.oxygen_remaining = person.oxygen_duration * 1.5
	_heart(8).advance(0.0)
	_expect(is_equal_approx(_heart(8).fill_ratio, 1.0), "The fill ratio is clamped to 1.0")
	person.oxygen_remaining = person.oxygen_duration

	# Colour thresholds follow the survivors' existing 55 s and 30 s warning levels.
	_expect(SurvivorHeart.oxygen_color(120.0) == SurvivorHeart.ACTIVE_COLOR, "Plenty of oxygen is teal-green")
	_expect(SurvivorHeart.oxygen_color(Survivor.WARNING_SECONDS) == SurvivorHeart.WARNING_COLOR, "At the 55 s warning level the heart is yellow-orange")
	_expect(SurvivorHeart.oxygen_color(42.0) == SurvivorHeart.WARNING_COLOR, "Between the levels it stays yellow-orange")
	_expect(SurvivorHeart.oxygen_color(Survivor.CRITICAL_SECONDS) == SurvivorHeart.CRITICAL_COLOR, "At the 30 s critical level it is red")
	_expect(SurvivorHeart.oxygen_color(5.0) == SurvivorHeart.CRITICAL_COLOR, "Below the critical level it stays red")
	var worst_jump := 0.0
	var seconds := 120.0
	while seconds > 0.0:
		worst_jump = maxf(worst_jump, _color_gap(SurvivorHeart.oxygen_color(seconds), SurvivorHeart.oxygen_color(seconds - 0.05)))
		seconds -= 0.05
	_expect(worst_jump < 0.01, "Colours change gradually with no jumps (largest step over 50 ms: %.4f)" % worst_jump)
	_set_oxygen(9, 50.0)
	_expect(_heart(9).fill_color() == SurvivorHeart.WARNING_COLOR, "A live heart at 50 s shows the warning colour")
	_set_oxygen(9, 20.0)
	_expect(_heart(9).fill_color() == SurvivorHeart.CRITICAL_COLOR and _heart(9).is_critical(), "A live heart at 20 s shows the critical colour")
	by_id[9].oxygen_remaining = by_id[9].oxygen_duration
	sections_done += 1


func _check_critical_pulse() -> void:
	sections_started += 1
	_set_oxygen(7, by_id[7].oxygen_duration) # Healthy
	_set_oxygen(8, 45.0) # Warning only
	_set_oxygen(9, 20.0) # Critical
	var healthy_range := _scale_range(7)
	var warning_range := _scale_range(8)
	var critical_range := _scale_range(9)
	_expect(is_equal_approx(healthy_range.y - healthy_range.x, 0.0) and is_equal_approx(healthy_range.y, 1.0), "A healthy heart never pulses")
	_expect(is_equal_approx(warning_range.y - warning_range.x, 0.0) and is_equal_approx(warning_range.y, 1.0), "A yellow-orange (warning) heart does not pulse either")
	_expect(critical_range.y - critical_range.x > 0.04, "A critical heart pulses (scale %.3f to %.3f)" % [critical_range.x, critical_range.y])
	_expect(critical_range.x >= 1.0 - 0.0001 and critical_range.y <= 1.10, "The pulse is subtle: never shrinks and grows by at most 10%")
	# Slow: no more than about two beats a second.
	var beats := 0
	var previous := _heart(9).visual_scale()
	var rising := false
	for step in range(0, 180):
		_heart(9).advance(STEP)
		var now := _heart(9).visual_scale()
		var now_rising := now > previous
		if rising and not now_rising:
			beats += 1
		rising = now_rising
		previous = now
	_expect(beats >= 3 and beats <= 6, "About %d beats in 3 s, calm rather than flashing" % beats)
	# Delivered / lost hearts never pulse, whatever their oxygen was.
	by_id[9].pick_up(false)
	by_id[9].deliver()
	_heart(9).advance(0.0)
	_tick(1.0)
	_expect(_heart(9).shown_state == Survivor.State.DELIVERED and is_equal_approx(_heart(9).visual_scale(), 1.0), "Once saved, a formerly critical heart stops pulsing")
	sections_done += 1


func _scale_range(id: int) -> Vector2:
	var low := 10.0
	var high := 0.0
	for step in range(0, 150):
		_heart(id).advance(STEP)
		low = minf(low, _heart(id).visual_scale())
		high = maxf(high, _heart(id).visual_scale())
	return Vector2(low, high)


func _check_aboard_and_delivered() -> void:
	sections_started += 1
	var before := _order()
	var person: Survivor = by_id[8]
	_set_oxygen(8, 60.0)
	var heart := _heart(8)
	var frozen_ratio := heart.fill_ratio
	# Board through the real game path.
	boat.global_position = person.global_position
	manager.try_interact()
	_expect(person.state == Survivor.State.ON_MAIN_BOAT and boat.passengers.size() == 1, "(setup) the main boat picks survivor 08 up: aboard, not delivered")
	heart.advance(0.0)
	_expect(heart.shown_state == Survivor.State.ON_MAIN_BOAT and heart.is_aboard(), "Boarding switches the heart to its aboard state")
	_expect(heart.fill_color() == SurvivorHeart.SECURED_COLOR, "The aboard heart uses the teal secured treatment")
	_expect(heart.is_animating(), "A confirmation animation starts on boarding")
	var peak := 0.0
	var steps := 0
	while heart.is_animating() and steps < 200:
		heart.advance(STEP)
		peak = maxf(peak, heart.visual_scale())
		steps += 1
	_expect(peak > 1.12 and peak < 1.4, "The boarding animation is a small scale pulse (peak %.2f)" % peak)
	_expect(steps * STEP <= SurvivorHeart.BOARD_DURATION + 0.05 and is_equal_approx(heart.visual_scale(), 1.0), "…brief (%.2f s) and it settles back to normal size" % (steps * STEP))
	_tick(2.0)
	_expect(is_equal_approx(heart.fill_ratio, frozen_ratio) and is_equal_approx(person.oxygen_remaining, 60.0), "Draining stops while aboard: the fill holds at %.2f" % frozen_ratio)
	_expect(manager.rescued_count == 0 and heart.shown_state != Survivor.State.DELIVERED, "Boarding is not delivering: nothing is counted as saved yet")
	_expect(_order() == before and hearts[7] == heart, "The heart keeps its place in the row")
	# Emergency boat passengers get the same treatment.
	by_id[3].pick_up(true)
	_heart(3).advance(0.0)
	_expect(_heart(3).shown_state == Survivor.State.ON_EMERGENCY_BOAT and _heart(3).is_aboard() and _heart(3).fill_color() == SurvivorHeart.SECURED_COLOR,
		"A survivor on the emergency boat shows the same aboard treatment")
	_tick(1.0)
	_expect(_heart(3).shown_state != Survivor.State.DELIVERED and manager.rescued_count == 0, "…and is not shown as delivered either")

	# Deliver through the real harbor interaction.
	boat.global_position = harbor.global_position
	manager.try_interact()
	_expect(person.state == Survivor.State.DELIVERED and manager.rescued_count == 1, "(setup) the survivor is delivered and counted")
	heart.advance(0.0)
	_expect(heart.shown_state == Survivor.State.DELIVERED, "Only on actual delivery does the heart show DELIVERED")
	_expect(is_equal_approx(heart.fill_ratio, 1.0) and heart.fill_color() == SurvivorHeart.SECURED_COLOR, "A delivered heart is completely filled in the saved colour")
	_expect(heart.is_animating(), "A short positive animation plays on delivery")
	peak = 0.0
	steps = 0
	while heart.is_animating() and steps < 200:
		heart.advance(STEP)
		peak = maxf(peak, heart.visual_scale())
		steps += 1
	_expect(peak > 1.2 and peak < 1.5 and steps * STEP <= SurvivorHeart.DELIVER_DURATION + 0.05 and is_equal_approx(heart.visual_scale(), 1.0),
		"The delivery pop peaks at %.2f over %.2f s and settles" % [peak, steps * STEP])
	_tick(3.0)
	_expect(heart.shown_state == Survivor.State.DELIVERED and heart.visible and is_equal_approx(heart.fill_ratio, 1.0), "The delivered heart stays on screen")
	_expect(_all_hearts_present() and _order() == before and hearts[7] == heart, "Still 15 hearts, same order, same place after boarding and delivery")
	# The survivor who boarded the emergency boat is delivered later.
	by_id[3].deliver()
	_heart(3).advance(0.0)
	_expect(_heart(3).shown_state == Survivor.State.DELIVERED, "An emergency-boat survivor turns DELIVERED when the boat unloads")
	sections_done += 1


func _check_lost_and_drain_live() -> void:
	sections_started += 1
	# Real engine frames: oxygen drains by itself, the heart follows it, then the survivor is lost.
	for heart: SurvivorHeart in hearts:
		heart.set_process(true) # Let the real _process drive them this time.
	var person: Survivor = by_id[6]
	var heart := _heart(6)
	var before := _order()
	var step_max := 0.0
	var last_fill := heart.fill_ratio
	var monotonic := true
	var tracks := true
	for frame in range(90):
		await physics_frame
		await process_frame
		step_max = maxf(step_max, last_fill - heart.fill_ratio)
		monotonic = monotonic and heart.fill_ratio <= last_fill + 0.000001
		last_fill = heart.fill_ratio
		tracks = tracks and absf(heart.fill_ratio - person.oxygen_remaining / person.oxygen_duration) < 0.01
	_expect(person.oxygen_remaining < person.oxygen_duration and heart.fill_ratio < 1.0, "With the game running, the heart really drains (%.3f left)" % heart.fill_ratio)
	_expect(monotonic and step_max < 0.003, "The drain is smooth: biggest per-frame drop %.5f" % step_max)
	_expect(tracks, "The heart never disagrees with the survivor's own oxygen by more than 1%")
	_expect(_heart(8).fill_ratio > 0.99, "A survivor with a long budget has barely moved")
	var lost_before := manager.lost_count
	person.oxygen_remaining = 0.05
	var saw_shake := false
	var min_scale := 10.0
	for frame in range(60):
		await physics_frame
		await process_frame
		if heart.shown_state == Survivor.State.LOST and heart.is_animating():
			saw_shake = saw_shake or absf(heart.visual_offset().x) > 0.3
			min_scale = minf(min_scale, heart.visual_scale())
	_expect(person.state == Survivor.State.LOST and manager.lost_count == lost_before + 1, "(setup) the survivor ran out of oxygen and was lost")
	_expect(heart.shown_state == Survivor.State.LOST and is_zero_approx(heart.fill_ratio), "When oxygen reaches zero the heart switches to the lost state, fully hollow of oxygen")
	_expect(saw_shake, "The lost animation shakes")
	_expect(is_equal_approx(heart.visual_scale(), SurvivorHeart.LOST_SCALE) and not heart.is_animating() and is_equal_approx(heart.visual_alpha(), 0.82) and heart.visual_offset() == Vector2.ZERO,
		"…then settles smaller and dimmer, without shaking")
	_expect(heart.fill_color() == SurvivorHeart.LOST_FILL and heart.fill_color().r > heart.fill_color().g * 2.0, "The lost heart is dark red")
	_expect(_all_hearts_present() and _order() == before and hearts[5] == heart, "The lost heart stays in its original place; the row still has 15 entries")
	for frame in range(30):
		await process_frame
	_expect(heart.shown_state == Survivor.State.LOST and not heart.is_pulsing(), "A lost heart stays lost and does not pulse")
	sections_done += 1


func _check_replay_reset() -> void:
	sections_started += 1
	by_id[1].pick_up(false)
	by_id[2].pick_up(true)
	by_id[2].deliver()
	by_id[3].oxygen_remaining = 0.0
	by_id[3].state = Survivor.State.LOST
	by_id[4].oxygen_remaining = 10.0
	for heart: SurvivorHeart in hearts:
		heart.advance(0.1)
	_expect(_heart(1).is_aboard() and _heart(2).shown_state == Survivor.State.DELIVERED and _heart(3).shown_state == Survivor.State.LOST,
		"(setup) hearts show aboard, delivered and lost")
	var order := _order()
	manager.restart_round()
	for heart: SurvivorHeart in hearts:
		heart.advance(0.0)
	var fresh := true
	for heart: SurvivorHeart in hearts:
		fresh = fresh and heart.shown_state == Survivor.State.ACTIVE and is_equal_approx(heart.fill_ratio, 1.0) and not heart.is_animating() \
			and (is_equal_approx(heart.visual_scale(), 1.0) or heart.is_pulsing()) and is_zero_approx(heart.visual_offset().length()) and is_equal_approx(heart.visual_alpha(), 1.0)
	_expect(fresh, "Replay resets all fifteen hearts to active and full, with no leftover animation")
	_expect(_all_hearts_present() and _order() == order, "Replay keeps the same fifteen hearts in the same order")
	sections_done += 1


func _check_pause_freezes_hearts() -> void:
	sections_started += 1
	_set_oxygen(9, 25.0)
	_expect(_heart(9).is_pulsing(), "(setup) a critical heart pulses in live play")
	for heart: SurvivorHeart in hearts:
		heart.set_process(true)
	main.call("_toggle_pause")
	_expect(paused, "(setup) the game is paused")
	await process_frame
	await process_frame
	var oxygen: float = by_id[9].oxygen_remaining
	var fill := _heart(9).fill_ratio
	for frame in range(30):
		await process_frame
	_expect(is_equal_approx(by_id[9].oxygen_remaining, oxygen) and is_equal_approx(_heart(9).fill_ratio, fill), "While paused the hearts stop draining with the game")
	_expect(not _heart(9).is_pulsing() and is_equal_approx(_heart(9).visual_scale(), 1.0), "…and the pulse stops too")
	main.call("_toggle_pause")
	await process_frame
	_expect(not paused and _heart(9).is_pulsing(), "After resuming, the pulse and the drain continue")
	sections_done += 1


## Windowed only: look at the pixels that were really drawn.
func _check_rendered_pixels() -> void:
	sections_started += 1
	for heart: SurvivorHeart in hearts:
		heart.set_process(true)
	_set_oxygen(8, by_id[8].oxygen_duration * 0.5)
	by_id[2].pick_up(false)
	by_id[4].pick_up(true)
	by_id[4].deliver()
	by_id[5].oxygen_remaining = 0.0
	by_id[5].state = Survivor.State.LOST
	for frame in range(90):
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var top := _top_panel()
	var row := top.find_child("SurvivorHearts", true, false) as Control
	var centre := func(id: int) -> Vector2:
		return top.global_position + row.position + _heart(id).position + Vector2(12, 12)
	var at := func(id: int, offset: Vector2) -> Color:
		var point: Vector2 = centre.call(id) + offset
		return image.get_pixel(int(point.x), int(point.y))
	var full: Color = at.call(9, Vector2(-5, -4)) # Upper left lobe of a full green heart.
	_expect(_color_gap(full, SurvivorHeart.ACTIVE_COLOR) < 0.12, "(pixels) a full heart is drawn teal-green (%s)" % full.to_html(false))
	var hollow_top: Color = at.call(8, Vector2(-5, -6))
	var filled_bottom: Color = at.call(8, Vector2(0, 5))
	_expect(hollow_top.get_luminance() < 0.2 and _color_gap(filled_bottom, SurvivorHeart.ACTIVE_COLOR) < 0.15,
		"(pixels) a half-drained heart is hollow on top and filled below (%s over %s)" % [hollow_top.to_html(false), filled_bottom.to_html(false)])
	var aboard: Color = at.call(2, Vector2(0, 0))
	_expect(aboard.g > aboard.r * 1.8 and aboard.get_luminance() < 0.5, "(pixels) an aboard heart is a dim teal fill with a bright outline (%s)" % aboard.to_html(false))
	var outline_found := false
	for dx in range(-14, 15):
		outline_found = outline_found or _color_gap(at.call(2, Vector2(dx, -2)), SurvivorHeart.SECURED_COLOR) < 0.2
	_expect(outline_found, "(pixels) the aboard heart has a teal outline")
	var saved: Color = at.call(4, Vector2(-6, -5))
	_expect(_color_gap(saved, SurvivorHeart.SECURED_COLOR) < 0.12, "(pixels) a delivered heart is solid teal (%s)" % saved.to_html(false))
	var tick_seen := false
	for dx in range(-8, 9):
		for dy in range(-4, 8):
			tick_seen = tick_seen or (at.call(4, Vector2(dx, dy)) as Color).get_luminance() < 0.25
	_expect(tick_seen, "(pixels) the delivered heart carries a dark check mark")
	var lost: Color = at.call(5, Vector2(6, -5))
	_expect(lost.r > lost.g * 1.8 and lost.get_luminance() < 0.3, "(pixels) a lost heart is dark red (%s)" % lost.to_html(false))
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
	_expect(sections_started == sections_done and sections_done >= 8, "Every test section ran to its end (%d of %d)" % [sections_done, sections_started])
	print("HUD SUITE: %d/%d checks passed" % [checks - failures.size(), checks])
	if is_instance_valid(main):
		main.queue_free()
	quit(0 if failures.is_empty() else 1)
