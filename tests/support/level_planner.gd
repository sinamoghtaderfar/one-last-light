class_name LevelPlanner
extends RefCounted
## Test support: the best rescue plan for a level, from real route lengths.
## A plan is an ordered list of survivors cut into trips of at most `capacity`. For every ordering
## and every cut the planner replays the trips and keeps the plan whose tightest oxygen reserve is
## largest. All times are seconds.

const PICKUP_STANDOFF := 34.0 ## The boat stops about this far from a survivor, inside the 48 px pickup ring.
const TURN_FACTOR := 1.06 ## Keyboard steering is 8-way, so real paths are a little longer than the geometric ones.
const TRIP_OVERHEAD := 3.0 ## Reading the oxygen timers and unloading in the harbor.
const PICKUP_OVERHEAD := 1.0

var routes: RoutePlanner
var harbor_gate: Vector2
var _cache: Dictionary = {}


func _init(planner: RoutePlanner, gate: Vector2) -> void:
	routes = planner
	harbor_gate = gate


## Route length in pixels between two points, from the real collision-aware route.
func distance(a: Vector2, b: Vector2) -> float:
	var key := "%d,%d>%d,%d" % [roundi(a.x), roundi(a.y), roundi(b.x), roundi(b.y)]
	if _cache.has(key):
		return _cache[key]
	var length := 0.0
	var at := a
	for point in routes.route(a, b):
		length += at.distance_to(point)
		at = point
	_cache[key] = length
	return length


## Leg length ending (or starting) at a survivor, shortened by the pickup standoff.
func leg(a: Vector2, b: Vector2, a_is_survivor: bool, b_is_survivor: bool) -> float:
	var length := distance(a, b)
	if a_is_survivor:
		length -= PICKUP_STANDOFF
	if b_is_survivor:
		length -= PICKUP_STANDOFF
	return maxf(length, 0.0)


## people: Array of {id, position, oxygen}. Returns the plan with the largest minimum reserve:
## {trips: Array[Array[int]], pickup_times: {id: seconds}, reserves: {id: seconds}, min_reserve, total_time}.
func best_plan(people: Array, capacity: int, speed: float, search_delay: float = 0.0) -> Dictionary:
	var best: Dictionary = {}
	for order in _permutations(people.size()):
		for cut_mask in range(1 << maxi(people.size() - 1, 0)):
			var plan := _replay(people, order, cut_mask, capacity, speed, search_delay)
			if plan.is_empty():
				continue
			if best.is_empty() or plan["min_reserve"] > best["min_reserve"]:
				best = plan
	return best


func _replay(people: Array, order: Array, cut_mask: int, capacity: int, speed: float, search_delay: float) -> Dictionary:
	var trips: Array = [[]]
	for index in range(order.size()):
		if index > 0 and (cut_mask >> (index - 1)) & 1 == 1:
			trips.append([])
		trips[trips.size() - 1].append(order[index])
	for trip in trips:
		if trip.size() > capacity:
			return {}
	var clock := search_delay
	var pickups: Dictionary = {}
	var reserves: Dictionary = {}
	var min_reserve := INF
	var ids: Array = []
	for trip in trips:
		var here := harbor_gate
		var here_is_survivor := false
		var trip_ids: Array = []
		for person_index in trip:
			var person: Dictionary = people[person_index]
			clock += leg(here, person["position"], here_is_survivor, true) * TURN_FACTOR / speed + PICKUP_OVERHEAD
			pickups[person["id"]] = clock
			reserves[person["id"]] = person["oxygen"] - clock
			min_reserve = minf(min_reserve, reserves[person["id"]])
			here = person["position"]
			here_is_survivor = true
			trip_ids.append(person["id"])
		clock += leg(here, harbor_gate, here_is_survivor, false) * TURN_FACTOR / speed + TRIP_OVERHEAD
		ids.append(trip_ids)
	return {"trips": ids, "pickup_times": pickups, "reserves": reserves, "min_reserve": min_reserve, "total_time": clock}


func _permutations(count: int) -> Array:
	var result: Array = []
	_permute(range(count), 0, result)
	return result


func _permute(items: Array, start: int, result: Array) -> void:
	if start >= items.size() - 1:
		result.append(items.duplicate())
		return
	for index in range(start, items.size()):
		var swapped := items.duplicate()
		var held = swapped[start]
		swapped[start] = swapped[index]
		swapped[index] = held
		_permute(swapped, start + 1, result)
