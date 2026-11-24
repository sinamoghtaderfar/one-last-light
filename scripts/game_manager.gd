class_name RescueGameManager
extends Node
## Runs the five-level campaign: builds each level from its LevelDefinition, coordinates pickup and
## delivery, applies the win and fail rules, and owns the economy between levels.

signal state_changed
signal notification(message: String, tone: String)
## A level was built: its survivors exist, nothing else has started.
signal level_loaded(level: LevelDefinition)
signal round_prepared
signal round_started
## Emitted exactly once per attempt, whatever the outcome.
signal round_ended
## A survivor's oxygen ran out (emitted before the win/fail check of that loss).
signal survivor_lost(survivor: Survivor)
## A survivor was seen for the first time in this attempt.
signal survivor_spotted(survivor: Survivor)
## A survivor was taken aboard / passengers were delivered at the harbor (for the speech bubbles).
signal survivor_boarded(survivor: Survivor)
signal survivors_delivered(count: int)
## E was pressed for a pickup while every seat is taken.
signal boat_full_refused
## A survivor in the water reached the critical (red) oxygen level.
signal survivor_critical(survivor: Survivor)
## The Oxygen Boost was used: every survivor in the water got extra seconds.
signal boost_applied(seconds: float)

enum Result { NONE, VICTORY, SURVIVOR_LOST, TIME_RAN_OUT }

const SURVIVOR_SCENE := preload("res://scenes/survivor.tscn")

@export var economy: RescueEconomy = RescueEconomy.new()
@export var levels: Array[LevelDefinition] = [
	preload("res://resources/levels/level_1.tres"),
	preload("res://resources/levels/level_2.tres"),
	preload("res://resources/levels/level_3.tres"),
	preload("res://resources/levels/level_4.tres"),
	preload("res://resources/levels/level_5.tres"),
]
@export var boat_spawn: Vector2 = Vector2(1020, 342)
## Every attempt scatters the survivors at random (see SurvivorLayout). Off: the level file's spots.
@export var randomize_layouts: bool = true

var boat: RescueBoat
var lighthouse: Lighthouse
var harbor: Harbor
var survivor_root: Node2D
var survivors: Array[Survivor] = []
var clock := LevelClock.new()
var level_index: int = 0
var level: LevelDefinition
var result: Result = Result.NONE
var delivered_count: int = 0
var lost_count: int = 0
var lost_ids: Array[int] = []
var round_active: bool = false
## The rating (1-3 stars) and the Light Points of the level that just succeeded.
var level_stars: int = 0
var level_points: int = 0
## True once a survivor was picked up with air already in the red zone: costs the third star.
var any_critical: bool = false
var campaign_complete: bool = false
## The Oxygen Boost is brought into this attempt (the player said yes before the level).
var boost_armed: bool = false
const BOOST_SECONDS := 15.0
var _warning_cooldown: float = 0.0
var layout: SurvivorLayout
## Seconds a player needs before the boat can move in a level whose boat waits (mouse + delay + sail-in).
const WAIT_MOUSE_SECONDS := 1.0
const WAIT_SAIL_IN_SECONDS := 3.0

var time_remaining: float:
	get: return clock.remaining
var elapsed_time: float:
	get: return clock.elapsed()
var level_number: int:
	get: return level.level_number if level != null else 1
var is_last_level: bool:
	get: return level_index >= levels.size() - 1
var points: int:
	get: return economy.points
var speed_level: int:
	get: return economy.speed_level
var survivors_total: int:
	get: return survivors.size()


func configure(player: RescueBoat, beacon: Lighthouse, dock: Harbor, spawn_root: Node2D) -> void:
	boat = player
	lighthouse = beacon
	harbor = dock
	survivor_root = spawn_root
	layout = SurvivorLayout.new(spawn_root.get_parent())
	economy.reset_campaign()
	load_level(0)


## Builds the chosen level: frees every survivor of the previous one and creates exactly this level's
## survivors, stopped and at full oxygen. Nothing carries over between levels.
func load_level(index: int) -> void:
	level_index = clampi(index, 0, levels.size() - 1)
	level = levels[level_index]
	round_active = false
	_clear_survivors()
	for spec in level.survivors:
		var person := SURVIVOR_SCENE.instantiate() as Survivor
		person.name = "Survivor%02d" % spec.survivor_id
		person.survivor_id = spec.survivor_id
		person.oxygen_duration = spec.oxygen_seconds
		person.position = spec.position
		survivor_root.add_child(person)
		person.discovered_now.connect(_on_survivor_discovered)
		person.lost.connect(_on_survivor_lost)
		person.turned_critical.connect(_on_survivor_critical)
		survivors.append(person)
	result = Result.NONE
	delivered_count = 0
	lost_count = 0
	lost_ids.clear()
	level_stars = 0
	level_points = 0
	any_critical = false
	boost_armed = false
	clock.reset(level.time_limit)
	apply_upgrades()
	_set_running(false)
	level_loaded.emit(level)
	state_changed.emit()


func _clear_survivors() -> void:
	for person in survivors:
		if is_instance_valid(person):
			survivor_root.remove_child(person) # Gone from the tree at once, so nothing counts it twice.
			person.queue_free()
	survivors.clear()


func _process(delta: float) -> void:
	if not round_active:
		return
	clock.advance(delta)
	if level.time_limit_enabled and time_remaining <= 0.0:
		_end_round(Result.TIME_RAN_OUT)
		return
	_warning_cooldown = maxf(0.0, _warning_cooldown - delta)
	for survivor in survivors:
		if survivor.state != Survivor.State.ACTIVE:
			continue
		var near_boat := boat.global_position.distance_to(survivor.global_position) <= boat.proximity_radius
		survivor.update_visibility(near_boat or lighthouse.is_illuminated(survivor.global_position), delta)


## Prepare and begin in one step. The game UI calls the two halves separately so a short
## intro can play between them; tests and scripted runs use this directly.
func start_round() -> void:
	prepare_round()
	begin_round()


## Resets the current level to its launch state with every gameplay system still stopped: clock at
## full time, oxygen full, the boat at the harbor, and the beam facing the harbor. Upgrades and the
## banked stars are untouched; stars from an unfinished attempt are dropped.
func prepare_round() -> void:
	round_active = false
	result = Result.NONE
	delivered_count = 0
	lost_count = 0
	lost_ids.clear()
	level_stars = 0
	level_points = 0
	any_critical = false
	clock.reset(level.time_limit)
	_warning_cooldown = 0.0
	boat.reset_boat(boat_spawn)
	apply_upgrades()
	_scatter_survivors()
	for survivor in survivors:
		survivor.reset_survivor()
	lighthouse.point_at(harbor.global_position)
	_set_running(false)
	round_prepared.emit()
	state_changed.emit()


## Switches every gameplay system on: clock, oxygen, the boat and the lighthouse.
func begin_round() -> void:
	if round_active:
		return
	_set_running(true)
	round_started.emit()
	state_changed.emit()
	notification.emit("Aim the light with your mouse to find the survivors.", "info")


func try_interact() -> void:
	if not round_active or get_tree().paused:
		return
	if harbor.contains_point(boat.global_position) and not boat.passengers.is_empty():
		var count := boat.unload_passengers().size()
		delivered_count += count
		notification.emit("Delivered %d to the harbor." % count, "success")
		survivors_delivered.emit(count)
		state_changed.emit()
		_check_round_completion()
		return
	if boat.is_full():
		_feedback("Boat full. Return to the harbor and press E to unload.", "warning")
		boat_full_refused.emit()
		return
	var nearest := nearest_survivor()
	if nearest == null:
		_feedback("Steer within the pickup ring of a survivor and press E.", "info")
		return
	var late := nearest.is_critical()
	if boat.try_board(nearest):
		if late:
			any_critical = true
		notification.emit("Survivor %02d aboard. Oxygen secured. %d/%d seats occupied." % [nearest.survivor_id, boat.passengers.size(), boat.capacity], "success")
		survivor_boarded.emit(nearest)
		state_changed.emit()


func nearest_survivor() -> Survivor:
	var nearest: Survivor = null
	var closest_distance := boat.pickup_radius
	for survivor in survivors:
		if survivor.state != Survivor.State.ACTIVE:
			continue
		var distance := boat.global_position.distance_to(survivor.global_position)
		if distance <= closest_distance:
			closest_distance = distance
			nearest = survivor
	return nearest


func active_count() -> int:
	var count := 0
	for survivor in survivors:
		if survivor.state == Survivor.State.ACTIVE:
			count += 1
	return count


func context_hint() -> String:
	if not round_active:
		return ""
	if harbor.contains_point(boat.global_position) and not boat.passengers.is_empty():
		return "Press E to Unload  ·  %d aboard" % boat.passengers.size()
	if boat.is_full():
		return "BOAT FULL  ·  Return to the harbor on the right and press E"
	var nearest := nearest_survivor()
	if nearest != null:
		return "Press E to Rescue  ·  air left %s" % nearest.air_text()
	return "WASD / arrows  Move     Mouse  Aim light     E  Rescue / unload     Esc  Pause"


## --- Campaign flow -------------------------------------------------------------------------

## A fresh random layout for this attempt; the level file's layout if none fits (or randomising is off).
func _scatter_survivors() -> void:
	var specs := level.survivors
	var pairs: Array = []
	if randomize_layouts:
		var budgets: Array = []
		for spec in specs:
			budgets.append(spec.oxygen_seconds)
		var wait := WAIT_MOUSE_SECONDS + level.boat_delay_after_mouse + WAIT_SAIL_IN_SECONDS if level.boat_waits_for_mouse else 0.0
		pairs = layout.generate(budgets, harbor.global_position, lighthouse.global_position, boat.base_speed, wait, level.show_mouse_cue)
	for index in range(survivors.size()):
		if index < pairs.size():
			survivors[index].configure(pairs[index]["position"], pairs[index]["oxygen"])
		else:
			survivors[index].configure(specs[index].position, specs[index].oxygen_seconds)


## The boat and the lighthouse take their values from what the economy owns.
func apply_upgrades() -> void:
	boat.apply_upgrades(economy.capacity, economy.speed_level)
	lighthouse.apply_light_level(economy.light_level)


## The shop sells for the furthest level the player has opened (replaying an early level does not
## hide upgrades that a later level already unlocked).
func next_level_number() -> int:
	return highest_unlocked()


## The shop is open between levels: after a won level, before moving on.
func can_shop() -> bool:
	return result == Result.VICTORY and not round_active and not campaign_complete


func shop_status(id: String) -> String:
	return economy.status(id, next_level_number())


func buy(id: String) -> bool:
	if not can_shop():
		return false
	if not economy.purchase(id, next_level_number()):
		return false
	apply_upgrades()
	notification.emit("%s bought." % ShopCatalog.title_of(id), "success")
	state_changed.emit()
	return true


## The rating of a won attempt: one star for finishing, one if nobody drowned, one if everyone you
## picked up still had air above the red zone. The two bonus stars are independent.
func rate_attempt() -> int:
	var rating := 1
	if lost_count == 0:
		rating += 1
	if not any_critical:
		rating += 1
	return rating


## Uses the armed Oxygen Boost: +15 s for every survivor still in the water. Once per campaign.
func activate_boost() -> bool:
	if not round_active or not boost_armed or not economy.use_boost():
		return false
	boost_armed = false
	for survivor in survivors:
		survivor.add_oxygen(BOOST_SECONDS)
	boost_applied.emit(BOOST_SECONDS)
	notification.emit("Oxygen Boost: +%d s for everyone in the water." % int(BOOST_SECONDS), "success")
	state_changed.emit()
	return true


## Moves on from a won level. Only legal after victory, once.
func advance_level() -> bool:
	if result != Result.VICTORY or round_active or campaign_complete:
		return false
	load_level(level_index + 1)
	return true


## Level N is open once Level N-1 has been won (at least one star). Level 1 is always open.
func is_unlocked(number: int) -> bool:
	return number == 1 or int(economy.best_stars.get(number - 1, 0)) >= 1


## The furthest level the player can play: the "you are here" of the level map.
func highest_unlocked() -> int:
	var number := 1
	while number < levels.size() and is_unlocked(number + 1):
		number += 1
	return number


## The level map's choice. Refused while a round runs or for a locked level.
func select_level(number: int) -> bool:
	if round_active or number < 1 or number > levels.size() or not is_unlocked(number):
		return false
	campaign_complete = false
	load_level(number - 1)
	return true


## Leaving a level for the map: stops everything without a result (no stars, no failure screen).
func abort_round() -> void:
	_set_running(false)
	result = Result.NONE
	state_changed.emit()


func replay_level() -> void:
	prepare_round()


## Intentional full reset: stars, upgrades, totals and progress.
func restart_campaign() -> void:
	economy.reset_campaign()
	campaign_complete = false
	load_level(0)


## Win: everything the level requires is delivered. Aboard is not delivered. Fail: the objective is
## out of reach because too many survivors were lost, or the clock ran out.
func _check_round_completion() -> void:
	if not round_active:
		return
	if lost_count > level.allowed_losses:
		_end_round(Result.SURVIVOR_LOST)
	elif delivered_count + lost_count == survivors.size() and delivered_count >= level.required_deliveries():
		_end_round(Result.VICTORY)


func _end_round(outcome: Result) -> void:
	if not round_active:
		return
	result = outcome
	_set_running(false)
	if outcome == Result.VICTORY:
		level_stars = rate_attempt()
		level_points = economy.commit_level(level_number, level_stars, delivered_count)
		campaign_complete = is_last_level
	state_changed.emit()
	round_ended.emit()


func _set_running(running: bool) -> void:
	round_active = running
	boat.controls_enabled = running
	boat.velocity = Vector2.ZERO
	lighthouse.enabled = running
	for survivor in survivors:
		survivor.set_process(running)


func _on_survivor_discovered(survivor: Survivor) -> void:
	survivor_spotted.emit(survivor)
	notification.emit("Survivor spotted · air left %s." % survivor.air_text(), "info")


func _on_survivor_critical(survivor: Survivor) -> void:
	if not round_active:
		return
	survivor_critical.emit(survivor)


func _on_survivor_lost(survivor: Survivor) -> void:
	if not round_active:
		return
	lost_count += 1
	lost_ids.append(survivor.survivor_id)
	notification.emit("Survivor %02d lost. Their oxygen ran out." % survivor.survivor_id, "danger")
	state_changed.emit()
	survivor_lost.emit(survivor)
	_check_round_completion()


func _feedback(message: String, tone: String) -> void:
	if _warning_cooldown <= 0.0:
		notification.emit(message, tone)
		_warning_cooldown = 0.7
