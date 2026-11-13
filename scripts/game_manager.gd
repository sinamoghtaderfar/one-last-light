class_name RescueGameManager
extends Node
## Coordinates launch, interactions and delivery across both boats.

signal state_changed
signal notification(message: String, tone: String)
signal round_started
signal round_ended

enum Result { NONE, VICTORY, TOO_MANY_LOST, TIME_RAN_OUT }

@export var economy: RescueEconomy = RescueEconomy.new()
@export_category("Level 1")
@export_range(1.0, 900.0) var level_duration: float = 240.0
@export_range(1, 15) var loss_limit: int = 3
@export var boat_spawn: Vector2 = Vector2(1020, 342)
@export_range(1.0, 64.0) var selection_radius: float = 22.0

var boat: RescueBoat
var emergency: EmergencyBoat
var lighthouse: Lighthouse
var harbor: Harbor
var survivors: Array[Survivor] = []
var clock := LevelClock.new()
var result: Result = Result.NONE
var main_delivered: int = 0
var emergency_delivered: int = 0
var lost_count: int = 0
var round_index: int = 1
var round_active: bool = false
var _warning_cooldown: float = 0.0

var time_remaining: float:
	get: return clock.remaining
var elapsed_time: float:
	get: return clock.elapsed()
var rescued_count: int:
	get: return main_delivered + emergency_delivered
var stars: int:
	get: return economy.stars
var stars_per_survivor: int:
	get: return economy.stars_per_survivor
var speed_level: int:
	get: return economy.speed_level


func configure(player: RescueBoat, beacon: Lighthouse, dock: Harbor, people: Array[Survivor], helper: EmergencyBoat) -> void:
	boat = player
	lighthouse = beacon
	harbor = dock
	emergency = helper
	survivors = people
	for survivor in survivors:
		survivor.discovered_now.connect(_on_survivor_discovered)
		survivor.lost.connect(_on_survivor_lost)
	emergency.configure(dock, boat.get_parent())
	emergency.delivered.connect(_on_emergency_delivered)
	clock.reset(level_duration)
	_set_running(false)
	state_changed.emit()


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


func start_round() -> void:
	result = Result.NONE
	main_delivered = 0
	emergency_delivered = 0
	lost_count = 0
	clock.reset(level_duration)
	_warning_cooldown = 0.0
	boat.reset_boat(boat_spawn)
	boat.apply_upgrades(0, speed_level)
	emergency.reset_boat()
	for survivor in survivors:
		survivor.reset_survivor()
	lighthouse.beam_angle = -PI
	_set_running(true)
	round_started.emit()
	state_changed.emit()
	notification.emit("Aim the light with your mouse. Right-click a visible survivor to send the emergency boat.", "info")


func try_interact() -> void:
	if not round_active or get_tree().paused:
		return
	if harbor.contains_point(boat.global_position) and not boat.passengers.is_empty():
		var count := boat.unload_passengers().size()
		main_delivered += count
		var earned := economy.credit_main_delivery(count)
		notification.emit("Main boat delivered %d to harbor. +%d stars." % [count, earned], "success")
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


func dispatch_at(point: Vector2) -> bool:
	if not round_active or get_tree().paused:
		return false
	if emergency.state != EmergencyBoat.State.READY:
		_feedback("Emergency boat unavailable. Check its status above the chart.", "warning")
		return false
	var target: Survivor = null
	var best := selection_radius
	for person in survivors:
		if person.state != Survivor.State.ACTIVE or not person.discovered:
			continue
		var distance := point.distance_to(person.global_position)
		if distance <= best:
			best = distance
			target = person
	if target == null or not emergency.dispatch(target):
		_feedback("Right-click a visible survivor within reach of the emergency boat.", "info")
		return false
	notification.emit("Emergency boat dispatched to survivor %02d." % target.survivor_id, "success")
	state_changed.emit()
	return true


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
	return "WASD / arrows  Move     Mouse  Aim light     Right-click  Dispatch     E  Rescue / unload     Esc  Pause"


func speed_cost() -> int:
	return economy.speed_cost()


func buy_speed_upgrade() -> bool:
	if result == Result.NONE or round_active or not economy.buy_speed_upgrade(round_index):
		return false
	boat.apply_upgrades(0, speed_level)
	notification.emit("Upgrade purchased. Main boat speed +%d%%." % roundi(speed_level * boat.speed_bonus_per_level * 100), "success")
	state_changed.emit()
	return true


func restart_round() -> void:
	start_round()


func _check_round_completion() -> void:
	# Only harbor deliveries and losses enter these counters. Either manifest can
	# still contain the last living passenger after the water is clear.
	if rescued_count + lost_count == survivors.size() and lost_count < loss_limit:
		_end_round(Result.VICTORY)


func _end_round(outcome: Result) -> void:
	if not round_active:
		return
	result = outcome
	_set_running(false)
	state_changed.emit()
	round_ended.emit()


func _set_running(running: bool) -> void:
	round_active = running
	boat.controls_enabled = running
	boat.velocity = Vector2.ZERO
	lighthouse.enabled = running
	emergency.set_running(running)
	for survivor in survivors:
		survivor.set_process(running)


func _on_emergency_delivered(count: int) -> void:
	if not round_active:
		return
	emergency_delivered += count
	notification.emit("Emergency boat delivered %d to harbor. No stars earned." % count, "success")
	state_changed.emit()
	_check_round_completion()


func _on_survivor_discovered(survivor: Survivor) -> void:
	notification.emit("Survivor %02d discovered · %ds oxygen remaining." % [survivor.survivor_id, ceili(survivor.oxygen_remaining)], "info")


func _on_survivor_lost(survivor: Survivor) -> void:
	if not round_active:
		return
	lost_count += 1
	notification.emit("Survivor %02d lost. Their oxygen ran out." % survivor.survivor_id, "danger")
	if lost_count >= loss_limit:
		_end_round(Result.TOO_MANY_LOST)
	else:
		state_changed.emit()
		_check_round_completion()


func _feedback(message: String, tone: String) -> void:
	if _warning_cooldown <= 0.0:
		notification.emit(message, tone)
		_warning_cooldown = 0.7
