class_name RescueGameManager
extends Node
## Owns the round, rescue accounting, and persistent between-round upgrades.

signal state_changed
signal notification(message: String, tone: String)
signal round_started
signal round_ended

@export_category("Rescue economy")
@export var stars_per_survivor: int = 3
@export var capacity_base_cost: int = 6
@export var speed_base_cost: int = 6
@export var upgrade_cost_step: int = 3
@export var maximum_upgrade_level: int = 3
@export_category("Round")
@export var boat_spawn: Vector2 = Vector2(1020, 342)

var boat: RescueBoat
var lighthouse: Lighthouse
var harbor: Harbor
var survivors: Array[Survivor] = []
var stars: int = 0
var rescued_count: int = 0
var lost_count: int = 0
var capacity_level: int = 0
var speed_level: int = 0
var round_index: int = 1
var elapsed_time: float = 0.0
var round_active: bool = false
var round_has_started: bool = false
var _warning_cooldown: float = 0.0


func configure(player: RescueBoat, beacon: Lighthouse, dock: Harbor, people: Array[Survivor]) -> void:
	boat = player
	lighthouse = beacon
	harbor = dock
	survivors = people
	for survivor in survivors:
		survivor.discovered_now.connect(_on_survivor_discovered)
		survivor.lost.connect(_on_survivor_lost)
	boat.controls_enabled = false
	lighthouse.enabled = false
	_set_oxygen_running(false)
	state_changed.emit()


func _process(delta: float) -> void:
	if not round_active:
		return
	elapsed_time += delta
	_warning_cooldown = maxf(0.0, _warning_cooldown - delta)
	for survivor in survivors:
		if survivor.state == Survivor.State.ACTIVE and not survivor.discovered:
			if lighthouse.is_illuminated(survivor.global_position):
				survivor.discover()
	_check_round_completion()


func start_round() -> void:
	rescued_count = 0
	lost_count = 0
	elapsed_time = 0.0
	_warning_cooldown = 0.0
	boat.reset_boat(boat_spawn)
	boat.apply_upgrades(capacity_level, speed_level)
	for survivor in survivors:
		survivor.reset_survivor()
	lighthouse.beam_angle = -PI
	lighthouse.enabled = true
	round_active = true
	round_has_started = true
	boat.controls_enabled = true
	_set_oxygen_running(true)
	round_started.emit()
	state_changed.emit()
	notification.emit("Search underway. Follow the beam; press E beside a marked survivor.", "info")


func try_interact() -> void:
	if not round_active:
		return
	if harbor.contains_point(boat.global_position):
		if boat.passengers.is_empty():
			_feedback("Harbor is safe. Find a marked survivor and press E to pick them up.", "info")
			return
		var delivered: Array[Survivor] = boat.unload_passengers()
		rescued_count += delivered.size()
		var earned: int = delivered.size() * stars_per_survivor
		stars += earned
		notification.emit("%d survivor%s rescued! +%d stars. Seats available again." % [delivered.size(), "" if delivered.size() == 1 else "s", earned], "success")
		state_changed.emit()
		_check_round_completion()
		return
	var nearest: Survivor = nearest_survivor()
	if nearest == null:
		_feedback("Move closer to a marked survivor. The lighthouse reveals their position.", "info")
		return
	if boat.is_full():
		_feedback("Boat full (%d/%d). Return to the harbor and press E to unload." % [boat.passengers.size(), boat.capacity], "warning")
		return
	if boat.try_board(nearest):
		notification.emit("Survivor %02d aboard. Oxygen secured. %d/%d seats occupied." % [nearest.survivor_id, boat.passengers.size(), boat.capacity], "success")
		state_changed.emit()


func nearest_survivor() -> Survivor:
	var nearest: Survivor = null
	var closest_distance: float = boat.pickup_radius
	for survivor in survivors:
		if survivor.state != Survivor.State.ACTIVE or not survivor.discovered:
			continue
		var distance: float = boat.global_position.distance_to(survivor.global_position)
		if distance <= closest_distance:
			closest_distance = distance
			nearest = survivor
	return nearest


func active_count() -> int:
	var count: int = 0
	for survivor in survivors:
		if survivor.state == Survivor.State.ACTIVE:
			count += 1
	return count


func discovered_count() -> int:
	var count: int = 0
	for survivor in survivors:
		if survivor.discovered and survivor.state == Survivor.State.ACTIVE:
			count += 1
	return count


func context_hint() -> String:
	if not round_active:
		return "Review results, improve your boat, and launch the next rescue."
	if harbor.contains_point(boat.global_position):
		if not boat.passengers.is_empty():
			return "[ E ]  Deliver %d passenger%s to safety" % [boat.passengers.size(), "" if boat.passengers.size() == 1 else "s"]
		return "SAFE HARBOR  ·  Follow the rotating beam to find survivors"
	var nearest: Survivor = nearest_survivor()
	if nearest != null:
		if boat.is_full():
			return "BOAT FULL  ·  Return to the harbor on the right; press E to unload"
		return "[ E ]  Pick up survivor %02d  ·  %ds oxygen" % [nearest.survivor_id, ceili(nearest.oxygen_remaining)]
	if active_count() == 0 and not boat.passengers.is_empty():
		return "All water contacts resolved  ·  Bring your passengers to the harbor →"
	if boat.is_full():
		return "BOAT FULL  ·  Bring your passengers to the harbor →"
	return "WASD / ARROWS  Move     E  Rescue / deliver     ESC  Pause"


func capacity_cost() -> int:
	return capacity_base_cost + capacity_level * upgrade_cost_step


func speed_cost() -> int:
	return speed_base_cost + speed_level * upgrade_cost_step


func buy_capacity_upgrade() -> bool:
	if not round_has_started or round_active or capacity_level >= maximum_upgrade_level or stars < capacity_cost():
		return false
	stars -= capacity_cost()
	capacity_level += 1
	boat.apply_upgrades(capacity_level, speed_level)
	state_changed.emit()
	return true


func buy_speed_upgrade() -> bool:
	if not round_has_started or round_active or speed_level >= maximum_upgrade_level or stars < speed_cost():
		return false
	stars -= speed_cost()
	speed_level += 1
	boat.apply_upgrades(capacity_level, speed_level)
	state_changed.emit()
	return true


func restart_round() -> void:
	# Retry preserves banked currency/upgrades; only people and round time reset.
	start_round()


func next_round() -> void:
	round_index += 1
	start_round()


func finish_round() -> void:
	# Never resolve a round while people are waiting or still aboard.
	if not round_active or active_count() > 0 or not boat.passengers.is_empty():
		return
	round_active = false
	boat.controls_enabled = false
	boat.velocity = Vector2.ZERO
	lighthouse.enabled = false
	_set_oxygen_running(false)
	state_changed.emit()
	round_ended.emit()


func _check_round_completion() -> void:
	if active_count() == 0 and boat.passengers.is_empty():
		finish_round()


func _set_oxygen_running(running: bool) -> void:
	for survivor in survivors:
		survivor.set_process(running)


func _on_survivor_discovered(survivor: Survivor) -> void:
	notification.emit("Contact %02d illuminated — %ds oxygen remaining." % [survivor.survivor_id, ceili(survivor.oxygen_remaining)], "info")
	state_changed.emit()


func _on_survivor_lost(survivor: Survivor) -> void:
	lost_count += 1
	notification.emit("Contact %02d lost. Their oxygen ran out." % survivor.survivor_id, "danger")
	state_changed.emit()
	_check_round_completion()


func _feedback(message: String, tone: String) -> void:
	if _warning_cooldown <= 0.0:
		notification.emit(message, tone)
		_warning_cooldown = 0.7
