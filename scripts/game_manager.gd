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
## Stars the level that just succeeded paid out.
var level_stars: int = 0
var campaign_complete: bool = false
## True between a successful level and the player moving on; upgrades can only be bought now.
var offers_open: bool = false
var _warning_cooldown: float = 0.0

var time_remaining: float:
	get: return clock.remaining
var elapsed_time: float:
	get: return clock.elapsed()
var level_number: int:
	get: return level.level_number if level != null else 1
var is_last_level: bool:
	get: return level_index >= levels.size() - 1
var stars: int:
	get: return economy.visible_stars()
var stars_per_survivor: int:
	get: return economy.stars_per_survivor
var speed_level: int:
	get: return economy.speed_level
var survivors_total: int:
	get: return survivors.size()


func configure(player: RescueBoat, beacon: Lighthouse, dock: Harbor, spawn_root: Node2D) -> void:
	boat = player
	lighthouse = beacon
	harbor = dock
	survivor_root = spawn_root
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
		survivors.append(person)
	result = Result.NONE
	delivered_count = 0
	lost_count = 0
	lost_ids.clear()
	level_stars = 0
	offers_open = false
	clock.reset(level.time_limit)
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
	if time_remaining <= 0.0:
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
	offers_open = false
	economy.discard_pending()
	clock.reset(level.time_limit)
	_warning_cooldown = 0.0
	boat.reset_boat(boat_spawn)
	boat.apply_upgrades(economy.capacity, economy.speed_level)
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
		var earned := economy.credit_delivery(count)
		notification.emit("Delivered %d to the harbor. +%d stars." % [count, earned], "success")
		state_changed.emit()
		_check_round_completion()
		return
	var nearest := nearest_survivor()
	if nearest == null:
		_feedback("Steer within the pickup ring of a survivor and press E.", "info")
		return
	if boat.is_full():
		_feedback("Boat full. Return to the harbor and press E to unload.", "warning")
		return
	if boat.try_board(nearest):
		notification.emit("Survivor %02d aboard. Oxygen secured. %d/%d seats occupied." % [nearest.survivor_id, boat.passengers.size(), boat.capacity], "success")
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
		return "Press E to Rescue  ·  Survivor %02d  ·  %ds oxygen" % [nearest.survivor_id, ceili(nearest.oxygen_remaining)]
	return "WASD / arrows  Move     Mouse  Aim light     E  Rescue / unload     Esc  Pause"


## --- Campaign flow -------------------------------------------------------------------------

## Offers of the level just won that can still be bought right now.
func available_offers() -> Array[UpgradeOffer]:
	var open: Array[UpgradeOffer] = []
	if not offers_open:
		return open
	for offer in level.upgrade_offers:
		if economy.preview(offer)["available"] and not is_offer_locked(offer):
			open.append(offer)
	return open


func purchase_offer(offer_id: StringName) -> bool:
	if not offers_open or round_active:
		return false
	var offer := level.offer_by_id(offer_id)
	if offer == null or is_offer_locked(offer):
		return false
	if not economy.purchase(offer, level.level_number):
		return false
	boat.apply_upgrades(economy.capacity, economy.speed_level)
	if offer.kind == UpgradeOffer.Kind.CAPACITY:
		notification.emit("Upgrade purchased. Boat capacity is now %d." % economy.capacity, "success")
	else:
		notification.emit("Upgrade purchased. Boat speed +%d%%." % roundi(economy.speed_level * boat.speed_bonus_per_level * 100), "success")
	state_changed.emit()
	return true


## With exclusive offers, a purchase from this level locks the remaining ones.
func is_offer_locked(offer: UpgradeOffer) -> bool:
	if not level.offers_exclusive:
		return false
	for other in level.upgrade_offers:
		if other != offer and economy.is_claimed(other):
			return true
	return false


## Moves on from a won level. Only legal after victory, once.
func advance_level() -> bool:
	if result != Result.VICTORY or round_active or campaign_complete:
		return false
	load_level(level_index + 1)
	return true


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
		level_stars = economy.commit_level(delivered_count)
		campaign_complete = is_last_level
		offers_open = level.offer_screen != LevelDefinition.OfferScreen.NONE and not campaign_complete
	else:
		economy.discard_pending()
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
	notification.emit("Survivor %02d discovered · %ds oxygen remaining." % [survivor.survivor_id, ceili(survivor.oxygen_remaining)], "info")


func _on_survivor_lost(survivor: Survivor) -> void:
	if not round_active:
		return
	lost_count += 1
	lost_ids.append(survivor.survivor_id)
	notification.emit("Survivor %02d lost. Their oxygen ran out." % survivor.survivor_id, "danger")
	state_changed.emit()
	_check_round_completion()


func _feedback(message: String, tone: String) -> void:
	if _warning_cooldown <= 0.0:
		notification.emit(message, tone)
		_warning_cooldown = 0.7
