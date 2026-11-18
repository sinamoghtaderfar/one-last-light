extends SceneTree
## godot --headless --fixed-fps 60 --path . --script res://tests/progression_suite.gd
## Covers the five-level campaign end to end, driven through the real Main scene: level data and
## survivor counts, the dynamic hearts, the Level 1 mouse cue, the upgrade popup and the
## prepare-for-Level-5 screen, the star economy, replay and restart, and the final victory screen.
## Physics (can the boat really reach everyone in time) is the balance suite's job; here the boat is
## placed by hand so that every rule of the campaign can be checked quickly and exactly.

const COUNTS := [1, 2, 4, 5, 6]
const SEA := Rect2(24, 116, 1104, 452)
const DT := 1.0 / 60.0

var checks: int = 0
var failures: Array[String] = []
var main: Node
var manager: RescueGameManager
var boat: RescueBoat
var lighthouse: Lighthouse
var harbor: Harbor
var cue: MouseCue
var round_starts: int = 0
var round_ends: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("Display: %s" % DisplayServer.get_name())
	await _boot()
	if main == null:
		_finish()
		return
	_check_level_data()
	_check_startup_state()
	await _boot()
	await _check_level_one_cue()
	await _boot()
	await _check_level_one_flow_and_popup()
	await _boot()
	await _check_declining_never_blocks()
	await _boot()
	await _check_full_campaign_with_upgrades()
	await _boot()
	await _check_full_campaign_without_upgrades()
	await _boot()
	await _check_level_five_capacity_branch()
	await _boot()
	await _check_economy_guards()
	await _boot()
	await _check_failure_and_replay()
	await _boot()
	await _check_restart_campaign()
	await _boot()
	_check_no_emergency_boat()
	_finish()


# --- scene helpers --------------------------------------------------------------------------

func _boot() -> void:
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
	lighthouse = main.get("lighthouse") as Lighthouse
	harbor = main.get("harbor") as Harbor
	cue = main.get("_cue") as MouseCue
	if not manager or not boat or not lighthouse or not harbor or not cue:
		_expect(false, "Main resolves the manager, boat, lighthouse, harbor and cue")
		main = null
		return
	round_starts = 0
	round_ends = 0
	manager.round_started.connect(func() -> void: round_starts += 1)
	manager.round_ended.connect(func() -> void: round_ends += 1)
	main.set_process(false) # The suite owns the intro clock.


func _launch_from_tutorial() -> void:
	for step in range(3):
		main.call("_tutorial_next")
	main.call("_launch_first_round")


## Runs the 3-second intro by hand. Checks, at several instants, that nothing runs underneath it.
func _play_intro(context: String) -> void:
	var limit := manager.level.time_limit
	var guard := 0
	var drained := false
	var full := true
	while main.get("_intro_active") == true and guard < 400:
		main.call("_advance_intro", DT)
		guard += 1
		if guard % 30 == 0:
			await process_frame
			for person in manager.survivors:
				full = full and is_equal_approx(person.oxygen_remaining, person.oxygen_duration) and person.state == Survivor.State.ACTIVE
			drained = drained or not is_equal_approx(manager.time_remaining, limit) or manager.round_active or boat.controls_enabled or lighthouse.enabled
	_expect(not drained and full, "%s: the intro runs with the clock at %d s, every oxygen tank full and the boat and beam off" % [context, int(limit)])
	_expect(main.get("_intro_active") == false and manager.round_active, "%s: gameplay starts when the intro ends" % context)


func _menu() -> Control:
	return main.get("_menu") as Control


func _node(node_name: String) -> Node:
	var menu := _menu()
	return null if menu == null else menu.find_child(node_name, true, false)


func _button(node_name: String) -> Button:
	return _node(node_name) as Button


func _menu_contains(fragment: String) -> bool:
	var menu := _menu()
	if menu == null:
		return false
	for label: Label in menu.find_children("*", "Label", true, false):
		if fragment.to_lower() in label.text.to_lower():
			return true
	return false


func _press(button: Button) -> void:
	if button != null:
		button.pressed.emit()


func _hud(column: String) -> String:
	return ((main.get("_stat_labels") as Dictionary)[column] as Label).text


func _hearts() -> Array:
	return main.get("_hearts")


## Counts every Survivor node anywhere in the running scene tree, not only under the spawn root.
func _survivor_nodes() -> int:
	var count := 0
	var pending: Array[Node] = [root]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if node is Survivor:
			count += 1
		pending.append_array(node.get_children())
	return count


## Puts the boat on each survivor and presses E, unloads at the harbor whenever it is full or
## nobody is left. Returns the number of unloads (trips). Mirrors what the real input does.
func _rescue_everyone() -> int:
	var trips := 0
	var guard := 0
	var most_aboard := 0
	while manager.round_active and guard < 60:
		guard += 1
		for person in manager.survivors:
			if person.state != Survivor.State.ACTIVE or boat.is_full():
				continue
			boat.global_position = person.global_position
			manager.try_interact()
			most_aboard = maxi(most_aboard, boat.passengers.size())
		boat.global_position = harbor.global_position
		if not boat.passengers.is_empty():
			trips += 1
		manager.try_interact()
	_expect(most_aboard <= boat.capacity, "The boat never carried more than its %d seats" % boat.capacity)
	return trips


# --- level data -----------------------------------------------------------------------------

func _check_level_data() -> void:
	_expect(manager.levels.size() == 5, "The campaign has exactly five levels and no sixth")
	for index in range(COUNTS.size()):
		manager.load_level(index)
		var level := manager.level
		var label := "Level %d" % (index + 1)
		_expect(level.level_number == index + 1, "%s is numbered %d" % [label, index + 1])
		_expect(manager.survivors.size() == COUNTS[index] and level.survivor_count() == COUNTS[index],
			"%s creates exactly %d survivors" % [label, COUNTS[index]])
		_expect(manager.survivor_root.get_child_count() == COUNTS[index] and _survivor_nodes() == COUNTS[index],
			"%s: only this level's survivors exist in the scene" % label)
		var ids := {}
		var spots := {}
		var oxygen_ok := true
		for person in manager.survivors:
			ids[person.survivor_id] = true
			spots[person.position] = true
			oxygen_ok = oxygen_ok and person.oxygen_duration > 0.0 and is_equal_approx(person.oxygen_remaining, person.oxygen_duration)
		_expect(ids.size() == COUNTS[index] and spots.size() == COUNTS[index], "%s: ids and positions are unique" % label)
		_expect(oxygen_ok, "%s: every survivor has its own positive oxygen budget" % label)
		_expect(level.time_limit == 240.0, "%s keeps the 4-minute clock" % label)
		_expect(level.show_mouse_cue == (index == 0), "%s: the mouse cue is %s" % [label, "on" if index == 0 else "off"])
		var hearts := _hearts()
		var row := main.get("_hearts_row") as Control
		_expect(hearts.size() == COUNTS[index] and row.get_child_count() == COUNTS[index],
			"%s shows exactly %d hearts" % [label, COUNTS[index]])
		var bound := true
		for heart: SurvivorHeart in hearts:
			bound = bound and is_instance_valid(heart.survivor) and heart.survivor in manager.survivors
		_expect(bound, "%s: every heart is bound to one of this level's survivors" % label)
		_expect(_hud("DELIVERED") == "0/%d" % COUNTS[index], "%s: the HUD shows 0/%d delivered" % [label, COUNTS[index]])
		_expect((main.get("_round_label") as Label).text == "LEVEL %d / 5" % (index + 1), "%s: the HUD names the level" % label)
	var offers := {1: 1, 2: 1, 3: 0, 4: 2, 5: 0}
	for index in range(COUNTS.size()):
		_expect(manager.levels[index].upgrade_offers.size() == offers[index + 1], "Level %d has %d upgrade offer(s)" % [index + 1, offers[index + 1]])
	manager.load_level(0)
	var offer_one := manager.levels[0].upgrade_offers[0]
	var offer_two := manager.levels[1].upgrade_offers[0]
	_expect(offer_one.kind == UpgradeOffer.Kind.CAPACITY and offer_one.cost == 3 and offer_one.amount == 1, "Level 1 offers +1 capacity for 3 stars")
	_expect(offer_two.kind == UpgradeOffer.Kind.CAPACITY and offer_two.cost == 6 and offer_two.amount == 1, "Level 2 offers +1 capacity for 6 stars")
	var speed := manager.levels[3].offer_by_id(&"l4_speed")
	var capacity := manager.levels[3].offer_by_id(&"l4_capacity")
	_expect(speed != null and speed.kind == UpgradeOffer.Kind.SPEED and speed.cost == 9, "The Level 5 choice offers speed for 9 stars")
	_expect(capacity != null and capacity.kind == UpgradeOffer.Kind.CAPACITY and capacity.cost == 9, "The Level 5 choice offers capacity for 9 stars")
	_expect(manager.levels[3].offers_exclusive and manager.levels[3].offer_screen == LevelDefinition.OfferScreen.PREPARE,
		"The Level 5 choice is exclusive and has its own screen")
	_expect(is_equal_approx(boat.speed_bonus_per_level, 0.18), "One speed upgrade is +18%")


func _check_startup_state() -> void:
	manager.load_level(0)
	_expect(manager.economy.capacity == 1 and boat.capacity == 1, "The boat starts with capacity 1")
	_expect(manager.economy.stars == 0 and manager.economy.speed_level == 0 and manager.stars == 0, "The campaign starts with no stars and no speed upgrade")
	_expect(manager.survivors.size() == 1 and _hearts().size() == 1, "Level 1 starts with one survivor and one heart")
	_expect(_hud("ABOARD") == "0/1", "The HUD shows the one-seat boat")


# --- level 1 --------------------------------------------------------------------------------

func _check_level_one_cue() -> void:
	_expect(not cue.is_playing() and not cue.visible, "The mouse cue is hidden before the level starts")
	_launch_from_tutorial()
	_expect(not cue.is_playing() and not cue.visible, "The mouse cue is hidden during the tutorial launch and the intro")
	for i in range(60):
		main.call("_advance_intro", DT)
	_expect(not cue.is_playing(), "The mouse cue stays hidden while the intro is running")
	await _play_intro("Level 1")
	_expect(cue.is_playing() and round_starts == 1, "The cue starts when gameplay activates")
	_expect(cue.elapsed < 0.0 and is_equal_approx(cue.alpha(), 0.0) and main.get("_go_remaining") > 0.0, "It stays invisible while the GO! flash is on screen, so the two never overlap")
	var guard_go := 0
	while cue.elapsed < 0.0 and guard_go < 200:
		await process_frame
		main.call("_advance_intro", DT) # Main's own _process is off in this suite; it runs the GO! countdown.
		guard_go += 1
	_expect(main.get("_go_remaining") == 0.0 and cue.is_playing() and cue.visible, "The cue then fades in, after the GO! flash has gone")
	_expect(cue.get_parent() == lighthouse, "The cue is anchored to the lighthouse")
	_expect(cue.global_position.is_equal_approx(lighthouse.global_position + cue.anchor_offset), "The cue sits at its offset from the lighthouse")
	var box := cue.box_rect()
	var placed := Rect2(cue.global_position + box.position, box.size)
	_expect(SEA.encloses(placed), "The cue panel lies inside the sea chart")
	_expect(not placed.has_point(lighthouse.global_position) and not placed.has_point(harbor.global_position) and not placed.has_point(manager.survivors[0].global_position),
		"The cue covers neither the lighthouse, the harbor nor the survivor")
	_expect(MouseCue.TITLE == "MOVE YOUR MOUSE" and MouseCue.SUBTITLE == "Aim the lighthouse beam to find the survivor.",
		"The cue shows MOVE YOUR MOUSE with the smaller aiming line")
	_expect(cue.find_children("*", "Control", true, false).is_empty() and cue.get_child_count() == 0, "The cue has no controls that could take input")
	_expect(is_equal_approx(cue.visible_seconds, 3.0), "The cue is set to last about 3 seconds")

	# Input is not blocked: the boat moves and the clock runs while the cue is up.
	var start_position := boat.global_position
	var start_time := manager.time_remaining
	Input.action_press("move_up")
	for i in range(20):
		await physics_frame
	Input.action_release("move_up")
	_expect(boat.global_position.distance_to(start_position) > 5.0 and manager.time_remaining < start_time and lighthouse.enabled,
		"The boat, the beam and the clock all work while the cue is showing")

	# It fades in, holds, and fades out.
	_expect(cue.alpha() > 0.0, "The cue fades in")
	while cue.is_playing() and cue.elapsed < 1.4:
		await process_frame
	_expect(cue.is_playing() and is_equal_approx(cue.alpha(), 1.0), "The cue is fully visible at mid-life")
	while cue.is_playing() and cue.elapsed < cue.visible_seconds - 0.2:
		await process_frame
	_expect(cue.is_playing() and cue.alpha() < 0.5, "The cue is fading out before it ends")
	var seen := cue.elapsed
	_expect(seen > 2.5, "The cue is still up after 2.5 seconds")

	# Pause freezes it.
	main.call("_toggle_pause")
	var frozen := cue.elapsed
	for i in range(20):
		await process_frame
	_expect(is_equal_approx(frozen, cue.elapsed) and cue.is_playing(), "Pause freezes the cue")
	main.call("_toggle_pause")
	var guard := 0
	while cue.is_playing() and guard < 200:
		await process_frame
		guard += 1
	_expect(not cue.is_playing() and not cue.visible, "The cue disappears by itself after about 3 seconds")
	_expect(cue.elapsed == 0.0, "The finished cue is reset")
	var later := round_starts
	for i in range(30):
		await process_frame
	_expect(not cue.is_playing() and not cue.visible and round_starts == later, "The cue does not come back during the same level")


func _check_level_one_flow_and_popup() -> void:
	_launch_from_tutorial()
	await _play_intro("Level 1")
	_expect(manager.survivors.size() == 1 and manager.round_active, "Level 1 is running with one survivor")
	var person := manager.survivors[0]
	_expect(person.global_position.distance_to(harbor.global_position) >= 600.0, "The Level 1 survivor is far from the harbor")

	boat.global_position = person.global_position
	manager.try_interact()
	_expect(person.state == Survivor.State.ON_BOAT and boat.passengers.size() == 1 and _hud("ABOARD") == "1/1",
		"The survivor can be rescued")
	_expect(manager.result == RescueGameManager.Result.NONE and manager.round_active and manager.delivered_count == 0 and _menu() == null and round_ends == 0,
		"Being aboard is not a win")
	_expect(manager.stars == 0, "A rescued survivor earns no stars until delivered")
	boat.global_position = harbor.global_position
	manager.try_interact()
	_expect(person.state == Survivor.State.DELIVERED and manager.delivered_count == 1, "Delivering the survivor completes the delivery")
	_expect(manager.result == RescueGameManager.Result.VICTORY and not manager.round_active and round_ends == 1, "Delivery wins Level 1 exactly once")
	_expect(manager.level_stars == 3 and manager.economy.stars == 3 and _hud("STAR BANK") == "3", "Three stars are earned and banked")
	_expect(_hud("DELIVERED") == "1/1", "The HUD shows 1/1 delivered")
	_expect(_menu_contains("LEVEL 1 COMPLETE"), "The popup says LEVEL 1 COMPLETE")
	_expect(_menu_contains("You earned 3 stars!"), "The popup says You earned 3 stars!")
	_expect(_menu_contains("Upgrade your boat capacity from 1 to 2 passengers?"), "The popup asks about capacity from 1 to 2 passengers")
	var upgrade := _button("OfferButton_l1_capacity")
	var not_now := _button("ContinueButton")
	_expect(upgrade != null and upgrade.text == "UPGRADE — 3 STARS" and not upgrade.disabled, "The popup has an enabled UPGRADE — 3 STARS button")
	_expect(not_now != null and not_now.text == "NOT NOW", "The popup has a NOT NOW button")
	manager._process(1000.0)
	manager.try_interact()
	manager._check_round_completion()
	manager._end_round(RescueGameManager.Result.TIME_RAN_OUT)
	manager._end_round(RescueGameManager.Result.VICTORY)
	_expect(round_ends == 1 and manager.economy.stars == 3 and manager.result == RescueGameManager.Result.VICTORY and manager.level_stars == 3,
		"Nothing pays or ends the level a second time, even when forced")

	_press(upgrade)
	_press(upgrade)
	_press(upgrade)
	_expect(manager.economy.capacity == 2 and boat.capacity == 2, "The upgrade raises capacity from 1 to 2, once")
	_expect(_menu_contains("Upgrade your boat capacity from 1 to 2 passengers?") and not _menu_contains("from 2 to 3"),
		"After buying, the popup still says 1 to 2 and does not advertise a further step")
	_expect(_menu_contains("1 of 1 survivor delivered"), "A single survivor is not pluralised")
	_expect(manager.economy.stars == 0 and _hud("STAR BANK") == "0", "The upgrade costs exactly 3 stars")
	_expect(manager.economy.purchases.size() == 1, "Pressing the upgrade three times bought it once")
	_expect(upgrade.disabled and upgrade.text == "PURCHASED", "The button shows PURCHASED afterwards")
	_expect(_button("ContinueButton").text == "CONTINUE TO LEVEL 2", "The popup now continues to Level 2")
	_expect(_menu_contains("Your boat now carries 2 passengers"), "The popup confirms the new capacity")
	_press(_button("ContinueButton"))
	_press(_button("ContinueButton")) # A second click must not skip Level 2.
	_expect(manager.level_number == 2 and manager.level_index == 1, "Continue goes to Level 2 and a double click does not skip it")
	_expect(main.get("_intro_active") == true and not manager.round_active, "Level 2 starts with the countdown")
	await _play_intro("Level 2")
	_expect(boat.capacity == 2 and _hud("ABOARD") == "0/2", "The purchased capacity is in the boat and on the HUD in Level 2")
	_expect(not cue.is_playing() and not cue.visible, "The mouse cue does not appear in Level 2")
	_expect(manager.survivors.size() == 2 and _hearts().size() == 2 and _survivor_nodes() == 2, "Level 2 has two survivors and two hearts, none left from Level 1")


func _check_declining_never_blocks() -> void:
	_launch_from_tutorial()
	await _play_intro("Level 1")
	_rescue_everyone()
	_press(_button("ContinueButton")) # NOT NOW
	_expect(manager.economy.capacity == 1 and manager.economy.stars == 3 and manager.economy.purchases.is_empty(), "NOT NOW buys nothing and keeps the stars")
	_expect(manager.level_number == 2, "NOT NOW continues to Level 2")
	await _play_intro("Level 2")
	_expect(boat.capacity == 1 and manager.survivors.size() == 2, "Level 2 is played with capacity 1")
	var trips := _rescue_everyone()
	_expect(trips == 2 and manager.result == RescueGameManager.Result.VICTORY, "Level 2 is won in two trips with capacity 1")
	_expect(manager.level_stars == 6 and manager.economy.stars == 9, "Two deliveries earn 6 stars and the bank is 3 + 6")
	_expect(_menu_contains("You earned 6 stars!"), "The Level 2 popup shows the stars earned")
	_expect(_menu_contains("Upgrade your boat capacity from 1 to 2 passengers?"), "A declined first upgrade is never skipped: the real values are shown, 1 to 2")
	var button := _button("OfferButton_l2_capacity")
	_expect(button != null and button.text == "UPGRADE — 6 STARS" and not button.disabled, "The Level 2 offer costs 6 stars")
	_press(button)
	_expect(manager.economy.capacity == 2 and manager.economy.stars == 3, "Capacity goes 1 to 2, never 1 to 3, and costs 6 stars")


# --- whole campaigns -------------------------------------------------------------------------

## Plays all five levels through the real screens. `buy` lists the offer ids to purchase.
func _play_campaign(label: String, buy: Array, expect_trips_equal_survivors: bool) -> void:
	var capacity := 1
	var speed := 0
	var bank := 0
	var rescued := 0
	var earned := 0
	var spent := 0
	_launch_from_tutorial()
	for index in range(5):
		var number := index + 1
		var ctx := "%s, Level %d" % [label, number]
		await _play_intro(ctx)
		_expect(manager.level_number == number and manager.survivors.size() == COUNTS[index], "%s: %d survivors" % [ctx, COUNTS[index]])
		_expect(_hearts().size() == COUNTS[index] and _survivor_nodes() == COUNTS[index], "%s: %d hearts and no stray survivors" % [ctx, COUNTS[index]])
		_expect(boat.capacity == capacity and is_equal_approx(boat.speed_multiplier, 1.0 + 0.18 * speed), "%s: the boat has capacity %d and speed +%d%%" % [ctx, capacity, roundi(18.0 * speed)])
		_expect(_hud("ABOARD") == "0/%d" % capacity and _hud("STAR BANK") == str(bank), "%s: the HUD shows %d seats and %d stars" % [ctx, capacity, bank])
		_expect(cue.is_playing() == (number == 1), "%s: the mouse cue is %s" % [ctx, "playing" if number == 1 else "absent"])
		var before_ends := round_ends
		var trips := _rescue_everyone()
		var expected_trips := ceili(float(COUNTS[index]) / capacity)
		_expect(trips == expected_trips, "%s: delivered in %d trip(s) with capacity %d" % [ctx, expected_trips, capacity])
		if expect_trips_equal_survivors:
			_expect(trips == COUNTS[index], "%s: solvable by carrying one survivor at a time" % ctx)
		_expect(manager.result == RescueGameManager.Result.VICTORY and manager.delivered_count == COUNTS[index] and round_ends == before_ends + 1,
			"%s: all %d delivered, one victory" % [ctx, COUNTS[index]])
		var paid: int = 3 * int(COUNTS[index])
		bank += paid
		earned += paid
		rescued += COUNTS[index]
		_expect(manager.level_stars == paid and manager.economy.stars == bank and _hud("STAR BANK") == str(bank), "%s: 3 stars per survivor, %d paid, bank %d" % [ctx, paid, bank])
		if number == 5:
			break
		_expect(_menu_contains("LEVEL %d COMPLETE" % number) and _menu_contains("You earned %d stars!" % paid), "%s: the complete screen shows the stars" % ctx)
		var offer_ids: Array = []
		for offer in manager.level.upgrade_offers:
			offer_ids.append(String(offer.id))
		if number == 3:
			_expect(offer_ids.is_empty() and _node("OfferButton_l3") == null, "%s: no upgrade is forced" % ctx)
			_expect(_button("ContinueButton").text == "CONTINUE TO LEVEL 4", "%s: a Continue button leads to Level 4" % ctx)
		if number == 4:
			_expect(_button("ContinueButton").text == "CONTINUE", "%s: completion unlocks the Level 5 choice" % ctx)
			_press(_button("ContinueButton"))
			_expect(_menu_contains("PREPARE FOR LEVEL 5") and _menu_contains("Six survivors are waiting. Choose your next boat upgrade."), "%s: the PREPARE FOR LEVEL 5 screen" % ctx)
			_expect(_node("OfferCard_l4_speed") != null and _node("OfferCard_l4_capacity") != null, "%s: both a speed and a capacity card" % ctx)
			_expect(_button("OfferButton_l4_speed").text == "UPGRADE — 9 STARS" and _button("OfferButton_l4_capacity").text == "UPGRADE — 9 STARS", "%s: each costs 9 stars" % ctx)
			_expect(_button("ContinueButton").text == "KEEP MY STARS", "%s: the screen offers KEEP MY STARS" % ctx)
			var detail := (_node("OfferCard_l4_speed").find_child("Detail", true, false) as Label).text
			_expect("+0% to +18%" in detail and "100 px/s to 118 px/s" in detail, "%s: the speed card shows the real before and after values (%s)" % [ctx, detail])
			var capacity_detail := (_node("OfferCard_l4_capacity").find_child("Detail", true, false) as Label).text
			_expect(("%d to %d passengers" % [capacity, capacity + 1]) == capacity_detail, "%s: the capacity card shows %d to %d (%s)" % [ctx, capacity, capacity + 1, capacity_detail])
		for id in offer_ids:
			if id in buy:
				var offer := manager.level.offer_by_id(StringName(id))
				var button := _button("OfferButton_" + id)
				_expect(button != null and not button.disabled, "%s: %s can be bought" % [ctx, id])
				_press(button)
				_press(button)
				spent += offer.cost
				bank -= offer.cost
				if offer.kind == UpgradeOffer.Kind.CAPACITY:
					capacity += 1
				else:
					speed += 1
				_expect(manager.economy.capacity == capacity and manager.economy.speed_level == speed and manager.economy.stars == bank,
					"%s: %s applied once; capacity %d, speed level %d, bank %d" % [ctx, id, capacity, speed, bank])
				if number == 4:
					var card_text := (_node("OfferCard_" + id).find_child("Detail", true, false) as Label).text
					if offer.kind == UpgradeOffer.Kind.SPEED:
						_expect("+0% to +18%" in card_text and "100 px/s to 118 px/s" in card_text and _button("OfferButton_" + id).text == "PURCHASED",
							"%s: the bought speed card still shows what was bought (%s)" % [ctx, card_text])
					else:
						_expect(("%d to %d passengers" % [capacity - 1, capacity]) == card_text, "%s: the bought capacity card still shows what was bought (%s)" % [ctx, card_text])
					for other in manager.level.upgrade_offers:
						if other.id != offer.id:
							var locked := _button("OfferButton_" + String(other.id))
							_expect(locked.disabled and locked.text == "LOCKED", "%s: the other Level 5 upgrade is locked" % ctx)
							_press(locked)
							_expect(manager.economy.capacity == capacity and manager.economy.speed_level == speed and manager.economy.stars == bank,
								"%s: pressing the locked upgrade changes nothing" % ctx)
		var proceed := _button("ContinueButton")
		if number == 4 and ("l4_speed" in buy or "l4_capacity" in buy):
			_expect(proceed.text == "START LEVEL 5", "%s: after buying, the screen says START LEVEL 5" % ctx)
		_press(proceed)
		_expect(manager.level_number == number + 1, "%s: moves on to Level %d" % [ctx, number + 1])
		_expect(main.get("_tutorial_open") == false and _node("TutorialTitle") == null, "%s: the tutorial does not reopen" % ctx)
	# The last level is done: the campaign summary.
	_expect(manager.campaign_complete and round_ends == 5, "%s: the campaign is complete after exactly five victories" % label)
	_expect(_menu_contains("ALL FIVE LEVELS COMPLETE"), "%s: the final screen says ALL FIVE LEVELS COMPLETE" % label)
	_expect(_menu_contains("Every survivor made it home"), "%s: the final screen has a victory message" % label)
	_expect(_menu_contains("Survivors rescued: %d" % rescued) and rescued == 18, "%s: 18 survivors rescued in total" % label)
	_expect(_menu_contains("Stars earned: %d" % earned) and earned == 54, "%s: 54 stars earned in total" % label)
	_expect(_menu_contains("Star bank: %d" % bank), "%s: the remaining bank is %d" % [label, bank])
	_expect(manager.economy.total_rescued == rescued and manager.economy.total_stars_earned == earned and earned - spent == bank, "%s: the economy totals agree with the screen" % label)
	var summary := (_node("UpgradeSummary") as Label).text
	if buy.is_empty():
		_expect("none" in summary, "%s: the summary lists no upgrades (%s)" % [label, summary])
	else:
		_expect(("%d passengers" % capacity) in summary and ("px/s" in summary), "%s: the summary lists the purchased upgrades and the final boat (%s)" % [label, summary])
		for id in buy:
			var offer: UpgradeOffer = null
			for level in manager.levels:
				if level.offer_by_id(StringName(id)) != null:
					offer = level.offer_by_id(StringName(id))
			_expect(("capacity +1" if offer.kind == UpgradeOffer.Kind.CAPACITY else "speed +18%") in summary, "%s: the summary mentions %s" % [label, id])
	_expect(_button("RestartButton") != null and _button("RestartButton").text == "RESTART CAMPAIGN", "%s: the final screen offers RESTART CAMPAIGN" % label)
	_expect(not manager.advance_level() and manager.level_number == 5, "%s: there is no sixth level" % label)
	_expect(_survivor_nodes() == 6 and _hearts().size() == 6, "%s: the last level still has exactly six survivors and hearts" % label)


func _check_full_campaign_with_upgrades() -> void:
	await _play_campaign("Full upgrades (speed branch)", ["l1_capacity", "l2_capacity", "l4_speed"], false)
	_expect(manager.economy.capacity == 3 and manager.economy.speed_level == 1 and manager.economy.stars == 36, "Speed branch ends with capacity 3, speed +18% and 36 stars")
	_expect(is_equal_approx(boat.speed_multiplier, 1.18), "The boat really moves 18% faster in Level 5")


func _check_full_campaign_without_upgrades() -> void:
	await _play_campaign("No upgrades", [], true)
	_expect(manager.economy.capacity == 1 and manager.economy.speed_level == 0 and manager.economy.stars == 54, "Declining everything ends with capacity 1, no speed and all 54 stars")


func _check_level_five_capacity_branch() -> void:
	await _play_campaign("Capacity branch", ["l1_capacity", "l2_capacity", "l4_capacity"], false)
	_expect(manager.economy.capacity == 4 and manager.economy.speed_level == 0, "The capacity branch ends with 4 seats and no speed upgrade")
	_expect(is_equal_approx(boat.speed_multiplier, 1.0), "The capacity branch does not change the boat's speed")


# --- economy guards --------------------------------------------------------------------------

func _check_economy_guards() -> void:
	_launch_from_tutorial()
	await _play_intro("Level 1")
	_rescue_everyone()
	var upgrade := _button("OfferButton_l1_capacity")
	manager.economy.stars = 2 # Fixture: one star short of the price.
	main.call("_refresh_offer_ui")
	_expect(upgrade.disabled and upgrade.text == "UPGRADE — 3 STARS", "With too few stars the button is disabled but shows the real price")
	_expect(_menu_contains("Not enough stars. You need 1 more."), "The popup says how many stars are missing")
	_press(upgrade)
	_expect(manager.economy.capacity == 1 and manager.economy.stars == 2 and boat.capacity == 1, "Without enough stars nothing is bought and no stars are taken")
	_expect(not manager.purchase_offer(&"l1_capacity") and manager.economy.stars >= 0, "The manager also refuses the purchase")
	_expect(not manager.purchase_offer(&"no_such_offer"), "An unknown offer is refused")
	_expect(_button("ContinueButton").text == "NOT NOW", "The player can still continue")
	manager.economy.stars = 3
	main.call("_refresh_offer_ui")
	_press(upgrade)
	_expect(manager.economy.capacity == 2 and manager.economy.stars == 0, "With enough stars the purchase goes through")

	# Offers are only open between levels.
	_press(_button("ContinueButton"))
	await _play_intro("Level 2")
	_expect(not manager.purchase_offer(&"l2_capacity"), "No purchase is possible while a level is running")
	_expect(manager.economy.capacity == 2 and manager.economy.stars == 0, "A refused mid-level purchase changes nothing")
	_expect(manager.economy.preview(manager.levels[1].upgrade_offers[0])["before"] == 2 and manager.economy.preview(manager.levels[1].upgrade_offers[0])["after"] == 3,
		"The Level 2 offer previews 2 to 3 once the first upgrade is owned")

	# The economy never exceeds its limits, whatever is asked.
	var economy := RescueEconomy.new()
	economy.stars = 1000
	var bought := 0
	for i in range(10):
		var offer := UpgradeOffer.new()
		offer.id = StringName("x%d" % i)
		offer.kind = UpgradeOffer.Kind.CAPACITY
		offer.cost = 1
		offer.amount = 1
		if economy.purchase(offer):
			bought += 1
	_expect(economy.capacity == economy.maximum_capacity and bought == economy.maximum_capacity - 1 and economy.stars == 1000 - bought,
		"Capacity stops at its maximum and no star is spent past it")


# --- failure and replay ----------------------------------------------------------------------

func _check_failure_and_replay() -> void:
	_launch_from_tutorial()
	await _play_intro("Level 1")
	# Fail Level 1 on the clock: the replay shows the cue again.
	manager._process(manager.time_remaining + 1.0)
	_expect(manager.result == RescueGameManager.Result.TIME_RAN_OUT and round_ends == 1 and not manager.round_active, "Level 1 fails when the clock runs out, once")
	_expect(_menu_contains("LEVEL 1 FAILED") and _menu_contains("Time ran out"), "The failure screen names the level and the reason")
	manager._process(10.0)
	_expect(round_ends == 1, "A finished attempt does not end a second time")
	_press(_button("ReplayButton"))
	_expect(main.get("_intro_active") == true and not manager.round_active and not cue.is_playing(), "Replay starts with the countdown and no cue yet")
	await _play_intro("Level 1 replay")
	_expect(cue.is_playing() and round_starts == 2, "The cue plays again on a Level 1 replay")
	_expect(manager.survivors.size() == 1 and _hearts().size() == 1 and _survivor_nodes() == 1, "A replay does not duplicate survivors or hearts")
	_rescue_everyone()
	_press(_button("OfferButton_l1_capacity"))
	_press(_button("ContinueButton"))
	await _play_intro("Level 2")
	_expect(manager.economy.capacity == 2 and manager.economy.stars == 0, "Upgrades survive into Level 2")

	# Level 2: deliver one of two, then run out of time. Pending stars are discarded.
	var first := manager.survivors[0]
	boat.global_position = first.global_position
	manager.try_interact()
	boat.global_position = harbor.global_position
	manager.try_interact()
	_expect(manager.delivered_count == 1 and manager.stars == 3 and manager.economy.stars == 0, "A delivery in an unfinished level shows stars on the HUD but does not bank them")
	manager._process(manager.time_remaining + 1.0)
	_expect(manager.result == RescueGameManager.Result.TIME_RAN_OUT and manager.economy.stars == 0 and manager.stars == 0 and round_ends == 3, "Failing a level discards its unbanked stars")
	_expect(_menu_contains("LEVEL 2 FAILED") and _button("ReplayButton").text == "REPLAY LEVEL 2", "The failure screen offers REPLAY LEVEL 2")
	_press(_button("ReplayButton"))
	await _play_intro("Level 2 replay")
	_expect(manager.level_number == 2 and manager.survivors.size() == 2 and boat.capacity == 2 and manager.economy.capacity == 2, "Replay keeps the level and its upgrades")
	_expect(not cue.is_playing(), "The cue does not appear on a Level 2 replay")
	_expect(is_equal_approx(manager.time_remaining, 240.0) and manager.delivered_count == 0 and manager.lost_count == 0, "Replay restores the clock and the counters")
	_expect(_survivor_nodes() == 2 and _hearts().size() == 2 and _hud("DELIVERED") == "0/2", "Replay restores two survivors, two hearts and the HUD")
	_expect(main.get("_tutorial_open") == false and _node("TutorialTitle") == null, "Replay does not reopen the tutorial")

	# Level 2 again, now lose a survivor to oxygen. Fails at once, the other survivor does not rescue it.
	var victim := manager.survivors[1]
	victim.oxygen_remaining = 0.0
	victim._process(0.1)
	_expect(victim.state == Survivor.State.LOST and manager.lost_count == 1 and manager.result == RescueGameManager.Result.SURVIVOR_LOST and round_ends == 4,
		"Losing a survivor fails the level at once, once")
	_expect(_menu_contains("LEVEL 2 FAILED") and _menu_contains("Survivor 02 was lost"), "The failure screen names the lost survivor")
	var hearts := _hearts()
	_expect(hearts.size() == 2 and (hearts[1] as SurvivorHeart).survivor == victim, "The heart for the lost survivor stays in place")
	_press(_button("ReplayButton"))
	await _play_intro("Level 2 second replay")
	_expect(manager.lost_count == 0 and victim.state == Survivor.State.ACTIVE and is_equal_approx(victim.oxygen_remaining, victim.oxygen_duration), "A lost survivor is restored by the replay")
	# Board without delivering is not a win, even when the clock then expires.
	for person in manager.survivors:
		boat.global_position = person.global_position
		manager.try_interact()
	_expect(manager.delivered_count == 0 and manager.result == RescueGameManager.Result.NONE, "Both survivors aboard is still not a win")
	manager._process(manager.time_remaining + 1.0)
	_expect(manager.result == RescueGameManager.Result.TIME_RAN_OUT and manager.economy.stars == 0, "Running out of time with everyone aboard is a failure that earns nothing")


# --- restart ---------------------------------------------------------------------------------

func _check_restart_campaign() -> void:
	_launch_from_tutorial()
	await _play_intro("Level 1")
	_rescue_everyone()
	_press(_button("OfferButton_l1_capacity"))
	_press(_button("ContinueButton"))
	await _play_intro("Level 2")
	_rescue_everyone()
	_press(_button("OfferButton_l2_capacity"))
	_press(_button("ContinueButton"))
	_expect(manager.economy.capacity == 3 and manager.level_number == 3, "Two upgrades bought and Level 3 reached")
	await _play_intro("Level 3")
	manager.economy.speed_level = 1 # Fixture, so the reset below has something of every kind to clear.
	manager.economy.stars = 20
	manager.restart_campaign()
	main.call("_begin_level_intro")
	await _play_intro("Restarted Level 1")
	var economy := manager.economy
	_expect(manager.level_number == 1 and manager.level_index == 0, "Restart returns to Level 1")
	_expect(economy.capacity == 1 and economy.speed_level == 0 and economy.stars == 0 and economy.pending_stars == 0, "Restart resets capacity, speed and stars")
	_expect(economy.total_rescued == 0 and economy.total_stars_earned == 0 and economy.purchases.is_empty(), "Restart resets the totals and the purchase history")
	_expect(boat.capacity == 1 and is_equal_approx(boat.speed_multiplier, 1.0) and _hud("ABOARD") == "0/1" and _hud("STAR BANK") == "0", "Restart gives the boat and the HUD their starting values")
	_expect(manager.survivors.size() == 1 and _hearts().size() == 1 and _survivor_nodes() == 1, "Restart rebuilds exactly one survivor and one heart")
	_expect(cue.is_playing(), "The cue plays again after a restart")
	_expect(not manager.campaign_complete and manager.result == RescueGameManager.Result.NONE, "Restart clears the campaign state")
	_rescue_everyone()
	var again := _button("OfferButton_l1_capacity")
	_expect(again != null and not again.disabled and again.text == "UPGRADE — 3 STARS", "After a restart the first upgrade can be bought again")
	_press(again)
	_expect(economy.capacity == 2 and economy.stars == 0 and economy.purchases.size() == 1, "The restarted campaign buys it exactly once")

	# Restart from the final screen's own button.
	manager.load_level(4)
	manager.economy.stars = 5
	main.call("_begin_level_intro")
	await _play_intro("Level 5")
	_rescue_everyone()
	_expect(manager.campaign_complete and _menu_contains("ALL FIVE LEVELS COMPLETE"), "Level 5 ends the campaign")
	var restart := _button("RestartButton")
	_press(restart)
	_press(restart)
	_expect(manager.level_number == 1 and manager.economy.stars == 0 and manager.economy.capacity == 1 and not manager.campaign_complete,
		"RESTART CAMPAIGN on the final screen resets everything")
	_expect(main.get("_intro_active") == true and _menu() == null, "Restart begins with the countdown and closes the screen")
	await _play_intro("Restart from the final screen")
	_expect(manager.survivors.size() == 1 and _hearts().size() == 1 and _survivor_nodes() == 1 and round_starts >= 1, "The restarted game is Level 1 with one survivor")


# --- the emergency boat is gone ---------------------------------------------------------------

func _check_no_emergency_boat() -> void:
	var offending: Array[String] = []
	var pending: Array[Node] = [main]
	var nodes := 0
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		nodes += 1
		var script := node.get_script() as Script
		var script_name := "" if script == null else script.resource_path.to_lower()
		if "emergency" in node.name.to_lower() or "emergency" in script_name:
			offending.append(str(node.get_path()))
		if node is Label and "emergency" in (node as Label).text.to_lower():
			offending.append("%s: %s" % [node.get_path(), (node as Label).text])
		if node is Button and ("emergency" in (node as Button).text.to_lower() or "dispatch" in (node as Button).text.to_lower()):
			offending.append(str(node.get_path()))
		pending.append_array(node.get_children())
	_expect(nodes > 20 and offending.is_empty(), "No emergency boat node, script or text exists in the running game (%s)" % ", ".join(offending))
	_expect(main.find_child("EmergencyBoat", true, false) == null and manager.get("emergency_boat") == null and not ("emergency" in str(manager.get_property_list()).to_lower()),
		"The manager has no emergency boat")
	_expect("emergency" not in str(main.get_property_list()).to_lower(), "Main has no emergency boat state")
	for action in InputMap.get_actions():
		_expect("emergency" not in String(action).to_lower() and "dispatch" not in String(action).to_lower(), "No input action %s refers to an emergency boat" % action)
	var boats := 0
	for node in main.find_children("*", "", true, false):
		if node is RescueBoat:
			boats += 1
	_expect(boats == 1, "There is exactly one boat in the scene")
	# Right click does nothing.
	for level_index in [0, 2]:
		manager.load_level(level_index)
		manager.prepare_round()
		manager.begin_round()
		var person := manager.survivors[0]
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_RIGHT
		event.position = person.get_global_transform_with_canvas().origin
		event.pressed = true
		root.push_input(event, true)
		event.pressed = false
		root.push_input(event, true)
		_expect(person.state == Survivor.State.ACTIVE and boat.passengers.is_empty() and manager.round_active, "A right click on a survivor in Level %d does nothing" % (level_index + 1))
	var text := FileAccess.get_file_as_string("res://scripts/main.gd").to_lower() + FileAccess.get_file_as_string("res://scripts/game_manager.gd").to_lower()
	_expect("emergency" not in text and "right_click" not in text and "mouse_button_right" not in text, "Neither the UI nor the manager scripts mention an emergency boat or a right-click dispatch")


func _expect(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("PASS: " + description)
	else:
		failures.append(description)
		push_error("FAIL: " + description)


func _finish() -> void:
	Input.action_release("move_up")
	print("PROGRESSION SUITE: %d/%d checks passed" % [checks - failures.size(), checks])
	if is_instance_valid(main):
		main.queue_free()
	quit(0 if failures.is_empty() else 1)
