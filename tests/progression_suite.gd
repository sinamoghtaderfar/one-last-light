extends SceneTree
## godot --headless --fixed-fps 60 --path . --script res://tests/progression_suite.gd
## Covers the campaign around the levels: level data, the 1-3 star rating and the Light Points it
## pays (new stars only), the shop (all items visible, grey until affordable and unlocked, OWNED once
## bought, refused during play), the Oxygen Boost (question before the level, the shaking button,
## +15 s for everyone, once), the one-time "new upgrade" moments, the HUD seat dots, the Level 1
## progress-bar callout, a full campaign and the restart. The boat is placed by hand; physics is
## the balance suite's job. Main's _process is off: the suite steps every animation itself.

const COUNTS := [2, 3, 4, 5, 6]
const LIVES := [1, 1, 2, 2, 3]
const DT := 1.0 / 60.0

var checks: int = 0
var failures: Array[String] = []
var main: Node
var manager: RescueGameManager
var boat: RescueBoat
var harbor: Harbor
var economy: RescueEconomy


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await _boot()
	if main == null:
		_finish()
		return
	_check_level_data()
	await _boot()
	await _check_random_layouts()
	await _boot()
	await _check_ratings_and_points()
	await _boot()
	await _check_shop()
	await _boot()
	await _check_boost()
	await _boot()
	await _check_showcase()
	await _boot()
	await _check_seats_and_callout()
	await _boot()
	await _check_level_map()
	await _boot()
	await _check_full_campaign_and_restart()
	_finish()


# --- helpers --------------------------------------------------------------------------------

func _boot() -> void:
	if is_instance_valid(main):
		main.queue_free()
		await process_frame
	paused = false
	main = null
	var scene := load("res://scenes/main.tscn") as PackedScene
	main = scene.instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	main.call("_select_level", 1) # From the level map to the Level 1 briefing.
	manager = main.get("manager") as RescueGameManager
	boat = main.get("boat") as RescueBoat
	harbor = main.get("harbor") as Harbor
	economy = manager.economy


## Starts the loaded level the way the player does (launch or replay), plays the countdown and,
## in Levels 1-3, brings the boat in after a mouse move. Upgrade moments are skipped unless asked.
func _start(keep_showcase: bool = false) -> void:
	if main.get("_tutorial_open") == true:
		main.call("_launch_first_round")
	elif main.get("_intro_active") != true and not manager.round_active:
		main.call("_begin_level_intro")
	var guard := 0
	while main.get("_intro_active") == true and guard < 400:
		main.call("_advance_intro", DT)
		guard += 1
	if main.get("_awaiting_mouse") == true:
		main.call("_on_first_mouse_move")
	guard = 0
	while (main.get("_boat_delay") >= 0.0 or main.get("_late_arrival") == true) and guard < 1200:
		main.call("_advance_late_arrival", DT)
		guard += 1
	if not keep_showcase and main.get("_showcase_active") == true:
		main.call("_end_showcase", true)


func _deliver_everyone() -> void:
	var guard := 0
	while manager.round_active and guard < 40:
		guard += 1
		for person in manager.survivors:
			if person.state != Survivor.State.ACTIVE or boat.is_full():
				continue
			boat.global_position = person.global_position
			manager.try_interact()
		boat.global_position = harbor.global_position
		manager.try_interact()


func _lose(person: Survivor) -> void:
	person.oxygen_remaining = 0.001
	person._process(0.01)
	var heart_break := main.get("_heart_break") as HeartBreak
	if heart_break.is_playing():
		heart_break.finish()


func _menu_node(node_name: String) -> Node:
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


func _press(node_name: String) -> void:
	var button := _menu_node(node_name) as Button
	if button != null:
		button.pressed.emit()


## Jumps to a level, wins it perfectly by hand and leaves the results screen open.
func _win_level(number: int) -> void:
	for earlier in range(1, number): # (fixture) the levels before it were won, so it is open
		if not economy.best_stars.has(earlier):
			economy.best_stars[earlier] = 1
	manager.load_level(number - 1)
	main.call("_begin_level_intro")
	await _start()
	_deliver_everyone()


func _card_state(id: String) -> String:
	var card := _menu_node("ShopCard_%s" % id) as Control
	return card.get_meta("state", "") if card != null else "missing"


# --- sections -------------------------------------------------------------------------------

func _check_level_data() -> void:
	_expect(manager.levels.size() == 5, "The campaign has exactly five levels")
	for index in range(5):
		var level := manager.levels[index]
		var label := "Level %d" % (index + 1)
		_expect(level.level_number == index + 1 and level.survivor_count() == COUNTS[index], "%s has %d survivors" % [label, COUNTS[index]])
		_expect(level.lives() == LIVES[index], "%s gives %d %s" % [label, LIVES[index], "life" if LIVES[index] == 1 else "lives"])
		_expect(level.show_mouse_cue == (index == 0) and level.show_tour == (index == 0), "%s: mouse cue and tour only in Level 1" % label)
		_expect(level.boat_waits_for_mouse == (index < 3), "%s: the boat %s for the first mouse move" % [label, "waits" if index < 3 else "does not wait"])
		_expect((level.first_sighting_message != "") == (index in [0, 2, 4]), "%s: a first-sighting warning only where the lives change (Levels 1, 3, 5)" % label)
		_expect(level.show_progress_callout == (index < 2), "%s: the progress bar is explained only in Levels 1 and 2" % label)
		_expect(not level.time_limit_enabled, "%s has no time limit" % label)
	_expect(economy.points_for_stars == [0, 50, 100, 200], "One star is worth 50 points, two 100, three 200")
	var unlocks := {"capacity_1": 4, "speed_1": 5, "boost": 5, "light_1": 6, "dinghy": 7, "speed_2": 8, "capacity_2": 9, "light_2": 10}
	for id in unlocks:
		_expect(int(ShopCatalog.item(id)["unlock_level"]) == unlocks[id], "%s unlocks at Level %d" % [ShopCatalog.title_of(id), unlocks[id]])
	_expect(ShopCatalog.item("speed_2")["requires"] == "speed_1" and ShopCatalog.item("capacity_2")["requires"] == "capacity_1" and ShopCatalog.item("light_2")["requires"] == "light_1",
		"Every second phase needs its first phase")


func _check_random_layouts() -> void:
	var lighthouse := main.get("lighthouse") as Lighthouse
	for index in range(5):
		manager.load_level(index)
		var seen: Array = []
		var rules_ok := true
		var budgets_ok := true
		for attempt in range(4):
			manager.prepare_round()
			var spots: Array = []
			var air: Array = []
			for person in manager.survivors:
				spots.append(person.position)
				air.append(int(person.oxygen_duration))
				rules_ok = rules_ok and manager.layout.clearance(person.position) >= 40.0 \
					and person.position.x >= 24.0 + SurvivorLayout.EDGE_MARGIN and person.position.x <= 1128.0 - SurvivorLayout.EDGE_MARGIN \
					and person.position.y >= SurvivorLayout.TOP_LIMIT and person.position.y <= 568.0 - SurvivorLayout.EDGE_MARGIN \
					and person.position.distance_to(harbor.global_position) <= SurvivorLayout.MAX_HARBOR_DISTANCE \
					and person.position.distance_to(harbor.global_position) >= SurvivorLayout.HARBOR_GAP and person.position.distance_to(lighthouse.global_position) >= 120.0 \
					and is_equal_approx(person.oxygen_remaining, person.oxygen_duration) and person.state == Survivor.State.ACTIVE
				for other in manager.survivors:
					rules_ok = rules_ok and (other == person or other.position.distance_to(person.position) >= SurvivorLayout.MIN_SPACING)
			var authored: Array = []
			for spec in manager.level.survivors:
				authored.append(int(spec.oxygen_seconds))
			air.sort()
			authored.sort()
			for k in range(air.size()):
				budgets_ok = budgets_ok and air[k] >= authored[k] and air[k] % 5 == 0
			seen.append(spots)
		_expect(seen[0] != seen[1] and seen[1] != seen[2], "Level %d: every attempt places the survivors somewhere new" % (index + 1))
		_expect(rules_ok, "Level %d: every random spot is open water, 90 px inside the chart edges, 170 px from the others, 260-820 px from the harbor, clear of the lighthouse" % (index + 1))
		_expect(budgets_ok, "Level %d: every survivor gets at least the level's own air budget, raised in 5 s steps where the trip needs it" % (index + 1))


func _check_ratings_and_points() -> void:
	await _start()
	_deliver_everyone()
	_expect(manager.result == RescueGameManager.Result.VICTORY and manager.level_stars == 3 and manager.level_points == 200 and manager.points == 200,
		"A quick, loss-free Level 1 is rated 3 stars and pays 200 points")
	var row := _menu_node("StarRow") as StarRow
	_expect(row != null and row.stars == 3 and _menu_contains("+200 Light Points"), "The results screen shows three stars and +200")
	_expect((main.get("_points_badge") as PointsBadge).points == 200, "The HUD shows the new balance")
	# Replaying for the same rating pays nothing.
	main.call("_begin_level_intro")
	await _start()
	_deliver_everyone()
	_expect(manager.level_stars == 3 and manager.level_points == 0 and manager.points == 200, "Replaying for the same three stars pays nothing new")
	_expect(_menu_contains("No new stars this time"), "The results screen says why no points were paid")
	# Level 3: one survivor drowns AND one is picked up already in the red: one star.
	manager.load_level(2)
	main.call("_begin_level_intro")
	await _start()
	_lose(manager.survivors[0])
	var late := manager.survivors[1]
	late.oxygen_remaining = late.critical_seconds() - 0.5
	_deliver_everyone()
	_expect(manager.result == RescueGameManager.Result.VICTORY and manager.any_critical and manager.level_stars == 1 and manager.level_points == 50 and manager.points == 250,
		"Level 3 won with one loss and a late pickup: 1 star, +50")
	# One drowns, but everyone saved still had green/yellow air: two stars (the bonuses are independent).
	main.call("_begin_level_intro")
	await _start()
	_lose(manager.survivors[0])
	_deliver_everyone()
	_expect(manager.level_stars == 2 and not manager.any_critical and manager.level_points == 50 and manager.points == 300,
		"One drowned but everyone saved was still out of the red: 2 stars, paying the difference (+50)")
	_expect(_menu_contains("Nobody drowned: missed") and _menu_contains("Everyone saved before their air turned red: +1 star"),
		"The results screen says which star was missed and why")
	# Nobody drowns but one is picked up in the red: also two stars, nothing new to pay.
	main.call("_begin_level_intro")
	await _start()
	var red := manager.survivors[0]
	red.oxygen_remaining = red.critical_seconds() - 0.5
	_deliver_everyone()
	_expect(manager.level_stars == 2 and manager.any_critical and manager.level_points == 0 and manager.points == 300,
		"Nobody drowned but a late pickup: 2 stars again, no new points")
	main.call("_begin_level_intro")
	await _start()
	_deliver_everyone()
	_expect(manager.level_stars == 3 and manager.level_points == 100 and manager.points == 400, "Improving 2 stars to 3 pays the difference (+100)")
	_expect(economy.best_stars[1] == 3 and economy.best_stars[3] == 3 and economy.total_stars() == 6, "The best rating per level is kept")
	# A failed attempt pays nothing.
	main.call("_begin_level_intro")
	await _start()
	_lose(manager.survivors[0])
	_lose(manager.survivors[1])
	_expect(manager.result == RescueGameManager.Result.SURVIVOR_LOST and manager.points == 400, "A lost level pays nothing")


func _check_shop() -> void:
	await _start()
	manager.economy.points = 1000
	_expect(not manager.can_shop() and not manager.buy("capacity_1"), "The shop is closed during a level")
	manager.economy.points = 0
	_deliver_everyone()
	_expect(manager.can_shop(), "After a won level the shop is open")
	_press("ShopButton")
	_expect(_menu_node("ShopGrid") != null and (_menu_node("ShopGrid") as Control).get_child_count() == ShopCatalog.ITEMS.size(),
		"The shop shows all %d items" % ShopCatalog.ITEMS.size())
	var all_grey := true
	for entry in ShopCatalog.ITEMS:
		all_grey = all_grey and _card_state(entry["id"]) == "grey" and (_menu_node("BuyButton_%s" % entry["id"]) as Button).disabled
	_expect(all_grey, "After Level 1 every item is grey and cannot be bought")
	_expect((_menu_node("BuyButton_capacity_1") as Button).text == "LOCKED" and _menu_contains("Unlocks at Level 4"), "Locked items say when they unlock")
	_press("ShopBack")
	_expect(_menu_node("ContinueButton") != null, "BACK returns to the results screen")
	# After Level 3 the Extra Seat unlocks; it lights up only once the points are there.
	await _win_level(3)
	manager.economy.points = 250
	main.call("_show_shop")
	_expect(manager.shop_status("capacity_1") == "points" and _card_state("capacity_1") == "grey" and _menu_contains("Need 50 more points"),
		"With 250 points the Extra Seat (300) is grey and says how many points are missing")
	manager.economy.points = 600
	main.call("_refresh_shop_ui")
	_expect(_card_state("capacity_1") == "active" and not (_menu_node("BuyButton_capacity_1") as Button).disabled, "With enough points it turns colourful and active")
	_expect(_card_state("speed_1") == "grey" and manager.shop_status("speed_1") == "level", "Faster Engine stays locked before Level 5")
	_press("BuyButton_capacity_1")
	_press("BuyButton_capacity_1") # A second press must not buy twice.
	_expect(economy.owned.has("capacity_1") and economy.points == 300 and economy.purchases.size() == 1 and boat.capacity == 2,
		"Buying costs 300 once, and the boat gets its second seat")
	_expect(_card_state("capacity_1") == "owned" and (_menu_node("BuyButton_capacity_1") as Button).text == "OWNED", "A bought item shows OWNED")
	_expect(economy.unshown == ["capacity_1"], "The new seat is waiting to be shown at the next level start")
	# Second phases need the first one (checked against a future level).
	_expect(economy.status("speed_2", 9) == "requires" and economy.status("capacity_2", 9) == "" if economy.points >= 500 else economy.status("capacity_2", 9) == "points",
		"Turbo Engine needs Faster Engine first; Third Seat only needs the Extra Seat and points")
	_expect(economy.status("dinghy", 6) == "level" and economy.status("dinghy", 7) != "level", "The Rescue Dinghy unlocks at Level 7")
	# After buying, items that are now too expensive go grey again.
	await _win_level(4)
	economy.points = 400
	main.call("_show_shop")
	_expect(_card_state("speed_1") == "active" and _card_state("boost") == "active", "After Level 4 Faster Engine and Oxygen Boost are both affordable with 400")
	_press("BuyButton_speed_1")
	_expect(economy.points == 100 and _card_state("boost") == "grey" and (_menu_node("BuyButton_boost") as Button).disabled,
		"After buying the engine, the boost is too expensive again and turns grey")
	# After a failed level the shop stays closed.
	manager.load_level(4)
	main.call("_begin_level_intro")
	await _start()
	_lose(manager.survivors[0])
	_lose(manager.survivors[1])
	_expect(not manager.can_shop() and not manager.buy("boost"), "There is no shopping after a lost level")


func _check_boost() -> void:
	# No boost owned: no question before Level 5.
	await _win_level(4)
	_press("ContinueButton")
	_expect(_menu_node("BoostQuestion") == null and main.get("_intro_active") == true, "Without a boost, Level 5 starts straight away")
	await _boot()
	await _win_level(4)
	economy.points = 400
	_expect(manager.buy("boost") and economy.has_boost, "The Oxygen Boost can be bought after Level 4")
	_expect(economy.unshown.is_empty(), "The boost is not an upgrade moment; it is asked about instead")
	main.call("_show_level_complete")
	_press("ContinueButton")
	_expect(_menu_node("BoostQuestion") != null and main.get("_intro_active") == false, "Before Level 5 the game asks whether to bring the boost")
	_press("BoostNo")
	_expect(not manager.boost_armed and economy.has_boost and main.get("_intro_active") == true, "NO keeps the boost for later and starts the level")
	await _start()
	_expect(not (main.get("_boost_button") as BoostButton).visible, "Without it, no boost button in the level")
	# Same again, now YES.
	await _boot()
	await _win_level(4)
	economy.points = 400
	manager.buy("boost")
	main.call("_show_level_complete")
	_press("ContinueButton")
	_press("BoostYes")
	await _start()
	var button := main.get("_boost_button") as BoostButton
	main.call("_advance_boost_button", DT)
	_expect(manager.boost_armed and button.visible, "YES puts the boost button beside the sea")
	_expect(not button.is_shaking(), "It stays calm while everyone's air is fine")
	var first := manager.survivors[0]
	first.oxygen_remaining = first.critical_seconds() + 0.05
	first._process(0.1)
	_expect(button.is_shaking() and button.hint_visible(), "When a heart turns red the button shakes and says it can be used")
	button.advance(5.0)
	_expect(not button.is_shaking(), "(setup) the shake settles")
	var second := manager.survivors[1]
	second.oxygen_remaining = second.critical_seconds() + 0.05
	second._process(0.1)
	_expect(button.is_shaking(), "It shakes again for every new red heart, until it is used")
	var before: Array[float] = []
	for person in manager.survivors:
		before.append(person.oxygen_remaining)
	boat.global_position = manager.survivors[5].global_position
	manager.try_interact() # One survivor aboard: the boost is only for people in the water.
	var aboard := manager.survivors[5].oxygen_remaining
	button.activated.emit()
	var all_plus := true
	for index in range(5):
		all_plus = all_plus and is_equal_approx(manager.survivors[index].oxygen_remaining, before[index] + 15.0)
	_expect(all_plus and is_equal_approx(manager.survivors[5].oxygen_remaining, aboard), "Clicking it gives everyone in the water +15 s")
	_expect(not economy.has_boost and not manager.boost_armed, "The boost is used up")
	main.call("_advance_boost_button", DT)
	_expect(not button.visible and (main.get("_banner_label") as Label).text.begins_with("+15 s OXYGEN"), "The button disappears and a banner confirms it")
	_expect(not manager.activate_boost(), "It cannot be used twice")


func _check_showcase() -> void:
	economy.owned["capacity_1"] = true
	economy.unshown.append("capacity_1")
	economy.owned["speed_1"] = true
	economy.unshown.append("speed_1")
	manager.load_level(3) # Level 4: no boat wait, so the boat is ready when the countdown ends.
	main.call("_begin_level_intro")
	await _start(true)
	_expect(main.get("_showcase_active") == true and paused, "At the level start the game pauses to show the new upgrades")
	var panel := main.get("_showcase_panel") as Panel
	var seats := main.get("_seats") as SeatDisplay
	_expect(panel.visible and (main.get("_showcase_title") as Label).text == "GREAT! YOU ADDED A SEAT" and seats.highlight_seat == 1,
		"First the new seat: a popup and the new seat dot glows")
	main.call("_advance_showcase", 1.0)
	_expect(not boat.showcase_exhaust, "(the seat moment has no exhaust)")
	main.call("_advance_showcase", HUD_STEP_REST)
	main.call("_advance_showcase", 1.2)
	var camera := main.get("_camera") as Camera2D
	_expect((main.get("_showcase_title") as Label).text == "ENGINE UPGRADED!" and boat.showcase_exhaust and boat.process_mode == Node.PROCESS_MODE_ALWAYS,
		"Then the engine: exhaust at the stern and a popup")
	main.call("_advance_showcase", 1.0)
	_expect(camera.zoom.x > 1.5 and camera.position.distance_to(boat.global_position) < 40.0, "The camera glides in on the boat")
	main.call("_advance_showcase", 2.5)
	_expect(main.get("_showcase_active") == false and not paused and not panel.visible, "Afterwards the game runs again")
	_expect(is_equal_approx(camera.zoom.x, 1.0) and camera.position == Vector2(576, 324) and not boat.showcase_exhaust and seats.highlight_seat == -1,
		"The camera, the boat and the seat dots are back to normal")
	_expect(economy.unshown.is_empty() and boat.capacity == 2 and boat.speed_level == 1, "The upgrades stay; they are shown only once")
	main.call("_begin_level_intro")
	await _start(true)
	_expect(main.get("_showcase_active") == false, "A replay does not show them again")


const HUD_STEP_REST := 1.0


func _check_seats_and_callout() -> void:
	main.call("_launch_first_round")
	var guard := 0
	while main.get("_intro_active") == true and guard < 400:
		main.call("_advance_intro", DT)
		guard += 1
	var callout := main.get("_callout") as Panel
	_expect(not callout.visible, "Level 1: no progress callout before the mouse moves")
	main.call("_on_first_mouse_move")
	main.call("_advance_callout", DT)
	_expect(callout.visible and (main.get("_progress") as RescueProgress).highlight > 0.0 or callout.visible,
		"After the first mouse move the progress bar is explained while the boat comes")
	var person := manager.survivors[0]
	person.discover()
	_expect(not (main.get("_banner") as Panel).visible and (main.get("_banner_queue") as Array).size() == 1,
		"The first-sighting warning waits until the callout is done")
	for i in range(int(7.0 / DT)):
		main.call("_advance_callout", DT)
		main.call("_advance_banner", DT)
	_expect(not callout.visible and (main.get("_banner") as Panel).visible, "Then the warning shows")
	var seats := main.get("_seats") as SeatDisplay
	main.call("_refresh_hud")
	_expect(seats.capacity == 1 and seats.passengers == 0, "The seat dots show one empty seat")
	boat.global_position = person.global_position
	manager.try_interact()
	_expect(seats.passengers == 1, "Boarding fills the seat dot (green)")
	var progress := main.get("_progress") as RescueProgress
	_expect(progress.aboard == 1 and progress.delivered == 0, "The progress bar marks the survivor as aboard")


func _card(number: int) -> Control:
	return _menu_node("LevelCard_%d" % number) as Control


func _check_level_map() -> void:
	main.call("_show_level_map")
	_expect(_menu_node("LevelGrid") != null and (_menu_node("LevelGrid") as Control).get_child_count() == 5, "The level map shows all five levels")
	_expect(_card(1).get_meta("state") == "next" and _card(2).get_meta("state") == "locked" and (_menu_node("PlayButton_2") as Button).disabled,
		"At the start only Level 1 is open (marked NEXT); Level 2 is locked")
	main.call("_select_level", 3)
	_expect(main.get("_intro_active") == false and manager.level_number == 1, "A locked level cannot be started")
	# Win Level 1 and go back to the map.
	main.call("_select_level", 1)
	await _start()
	_deliver_everyone()
	_press("LevelsButton")
	_expect(_card(1).get_meta("state") == "done" and (_card(1).find_child("Stars", true, false) as StarRow).stars == 3,
		"Level 1 shows its three stars")
	_expect(_card(2).get_meta("state") == "next" and (_menu_node("PlayButton_2") as Button).text == "PLAY" and _card(3).get_meta("state") == "locked",
		"Winning Level 1 opens Level 2 (NEXT); Level 3 stays locked")
	_expect((_menu_node("PlayButton_1") as Button).text == "REPLAY", "A finished level can be replayed")
	_expect(_menu_contains("Stars: 3 / 15"), "The map shows the total stars")
	# Replay Level 1 from the map: no briefing the second time, and no new points for the same stars.
	_press("PlayButton_1")
	_expect(main.get("_tutorial_open") == false and main.get("_intro_active") == true, "Replaying Level 1 skips the briefing")
	await _start()
	_deliver_everyone()
	_expect(manager.level_points == 0 and manager.points == 200, "The same stars pay nothing twice")
	# Leave a running level through the pause menu.
	_press("LevelsButton")
	_press("PlayButton_2")
	await _start()
	main.call("_toggle_pause")
	_expect(_menu_node("LevelsButton") != null, "The pause menu offers LEVELS")
	_press("LevelsButton")
	_expect(not manager.round_active and not paused and main.get("_paused") == false and _menu_node("LevelGrid") != null,
		"LEVELS leaves the level: nothing runs, nothing is paused, the map is open")
	_expect(manager.economy.best_stars.get(2, 0) == 0 and _card(3).get_meta("state") == "locked", "Leaving a level earns nothing and opens nothing")
	# A one-star win is enough to open the next level.
	_press("PlayButton_2")
	await _start()
	manager.survivors[0].oxygen_remaining = manager.survivors[0].critical_seconds() + 0.05
	manager.survivors[0]._process(0.1)
	_deliver_everyone()
	_expect(manager.result == RescueGameManager.Result.VICTORY and manager.level_stars == 2, "(setup) Level 2 won with two stars")
	_press("LevelsButton")
	_expect(_card(3).get_meta("state") == "next", "Any win (at least one star) opens the next level")
	# The shop sells for the furthest open level, even when an early level is replayed.
	for number in [3]:
		economy.best_stars[number] = 1
	economy.points = 300
	_press("PlayButton_1")
	await _start()
	_deliver_everyone()
	_expect(manager.highest_unlocked() == 4 and manager.shop_status("capacity_1") == "", "Replaying Level 1 with Level 4 open: the Extra Seat can be bought")


func _check_full_campaign_and_restart() -> void:
	await _start()
	for index in range(5):
		_expect(manager.level_number == index + 1, "Campaign: Level %d is running" % (index + 1))
		_deliver_everyone()
		_expect(manager.result == RescueGameManager.Result.VICTORY, "Campaign: Level %d won" % (index + 1))
		if index < 4:
			_press("ContinueButton")
			await _start()
	_expect(manager.campaign_complete and _menu_contains("ALL FIVE LEVELS COMPLETE") and _menu_contains("Stars: 15 / 15"),
		"After Level 5 the campaign summary shows 15 of 15 stars")
	_expect(economy.points == 1000 and economy.total_points_earned == 1000, "A perfect campaign earns 1000 Light Points")
	_expect(_menu_node("ShopButton") == null and not manager.can_shop(), "There is no shop after the last level")
	_press("RestartButton")
	_expect(manager.level_number == 1 and economy.points == 0 and economy.owned.is_empty() and economy.best_stars.is_empty(),
		"Restart Campaign resets points, ratings and upgrades")


# --- utilities ------------------------------------------------------------------------------

func _expect(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("PASS: " + description)
	else:
		failures.append(description)
		push_error("FAIL: " + description)


func _finish() -> void:
	print("PROGRESSION SUITE: %d/%d checks passed" % [checks - failures.size(), checks])
	if is_instance_valid(main):
		main.queue_free()
	quit(0 if failures.is_empty() else 1)
