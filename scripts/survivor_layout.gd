class_name SurvivorLayout
extends RefCounted
## Scatters a level's survivors at random over open water for every attempt, so a replay never
## looks the same. The level file's positions are only the fallback.
##
## Rules for a spot: at least 40 px of clear water from every rock and the island, EDGE_MARGIN from
## the chart's sides and bottom (and below the banner strip at the top), at least MIN_SPACING from
## every other survivor, between HARBOR_GAP and MAX_HARBOR_DISTANCE from the harbor, LANDMARK_GAP
## from the lighthouse, and outside the Level 1 mouse hint. Of CANDIDATES draws the most spread-out
## one is kept (largest smallest distance between two survivors), so they never bunch up.
##
## Then the air: the level's own budgets go smallest-to-nearest, and each is raised (fit_air) until
## a beginner with the starting boat, fetching one survivor per trip nearest first, still arrives
## with at least 40% of that survivor's air left, well before the red zone at a quarter. So a far
## survivor always gets enough air for the trip, and every layout is fair however it falls.

const SEA := Rect2(24, 116, 1104, 452)
const CLEARANCE := 40.0
## Room to the chart's left, right and bottom edge, so the marker and its "AIR" label sit well inside.
const EDGE_MARGIN := 90.0
## Longest straight line from the harbor: nobody is put so far away that the trip itself is the problem.
const MAX_HARBOR_DISTANCE := 820.0
## Nobody floats in the top strip where the warning banner and the progress callout appear.
const TOP_LIMIT := 190.0
const MIN_SPACING := 170.0
const HARBOR_GAP := 260.0
const LANDMARK_GAP := 120.0
## Valid layouts compared before the most spread-out one is chosen.
const CANDIDATES := 40
## The Level 1 hint panel above the lighthouse, with a margin.
const CUE_AREA := Rect2(390, 150, 292, 148)
## Planning model, sized for a beginner rather than a perfect player: routes bend around rocks
## (DETOUR), a person hesitates before each trip, and everyone must still have 40% of their air
## when the boat arrives, which leaves a clear margin before the red zone at a quarter.
const DETOUR := 1.4
const THINK_SECONDS := 3.5
const PICKUP_SECONDS := 1.0
const UNLOAD_SECONDS := 1.5
const MIN_AIR_SHARE := 0.4

var rng := RandomNumberGenerator.new()
var _shapes: Array[CollisionShape2D] = []


func _init(world: Node) -> void:
	rng.randomize()
	for node in world.find_children("*", "CollisionShape2D", true, false):
		var shape := node as CollisionShape2D
		if shape.get_parent() is CharacterBody2D or shape.get_parent() is Area2D:
			continue # The boat and trigger areas are not obstacles.
		_shapes.append(shape)


## Returns [{position, oxygen}] in survivor order, or an empty array to keep the level file's layout.
## start_delay: seconds before the boat can move (the Levels 1-3 wait). avoid_cue: Level 1.
func generate(budgets: Array, harbor: Vector2, lighthouse: Vector2, speed: float, start_delay: float, avoid_cue: bool) -> Array:
	var best: Array = []
	var best_score := -1.0
	for attempt in range(CANDIDATES):
		var spots: Array = []
		for index in range(budgets.size()):
			var spot := _pick(spots, harbor, lighthouse, MAX_HARBOR_DISTANCE, avoid_cue)
			if spot == Vector2.INF:
				break
			spots.append(spot)
		if spots.size() != budgets.size():
			continue
		var score := spread(spots)
		if score > best_score:
			best_score = score
			best = spots
	if best.is_empty():
		return []
	best.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.distance_to(harbor) < b.distance_to(harbor))
	var air := fit_air(best, budgets, harbor, speed, start_delay)
	# Hand the pairs out in random survivor order, so ids say nothing about distance either.
	var pairs: Array = []
	for index in range(best.size()):
		pairs.append({"position": best[index], "oxygen": air[index]})
	_shuffle(pairs)
	return pairs


## The level's own budgets, smallest to the nearest survivor, each raised (in 5-second steps) until a
## beginner with the starting boat, one trip each, nearest first, arrives with MIN_AIR_SHARE of it
## left. Spots must be sorted by distance from the harbor.
func fit_air(spots: Array, budgets: Array, harbor: Vector2, speed: float, start_delay: float) -> Array:
	var sorted_budgets := budgets.duplicate()
	sorted_budgets.sort()
	var air: Array = []
	var clock := start_delay
	for index in range(spots.size()):
		var leg := (spots[index] as Vector2).distance_to(harbor) * DETOUR / speed
		clock += THINK_SECONDS + leg + PICKUP_SECONDS
		var needed := ceilf(clock / (1.0 - MIN_AIR_SHARE) / 5.0) * 5.0
		air.append(maxf(float(sorted_budgets[index]), needed))
		clock += leg + UNLOAD_SECONDS
	return air


## The smallest distance between two survivors (a single survivor counts as fully spread).
static func spread(spots: Array) -> float:
	var smallest := INF
	for a in range(spots.size()):
		for b in range(a + 1, spots.size()):
			smallest = minf(smallest, (spots[a] as Vector2).distance_to(spots[b]))
	return 9999.0 if smallest == INF else smallest


func clearance(point: Vector2) -> float:
	var smallest := INF
	for collider in _shapes:
		if collider.shape is CircleShape2D:
			smallest = minf(smallest, collider.global_position.distance_to(point) - (collider.shape as CircleShape2D).radius)
		elif collider.shape is RectangleShape2D:
			var size := (collider.shape as RectangleShape2D).size
			var rect := Rect2(collider.global_position - size * 0.5, size)
			var nearest := Vector2(clampf(point.x, rect.position.x, rect.end.x), clampf(point.y, rect.position.y, rect.end.y))
			smallest = minf(smallest, nearest.distance_to(point))
	return smallest


func _pick(taken: Array, harbor: Vector2, lighthouse: Vector2, reach: float, avoid_cue: bool) -> Vector2:
	for tries in range(500):
		var point := Vector2(rng.randf_range(SEA.position.x + EDGE_MARGIN, SEA.end.x - EDGE_MARGIN), rng.randf_range(TOP_LIMIT, SEA.end.y - EDGE_MARGIN)).round()
		var from_harbor := point.distance_to(harbor)
		if from_harbor < HARBOR_GAP or from_harbor > reach or point.distance_to(lighthouse) < LANDMARK_GAP:
			continue
		if avoid_cue and CUE_AREA.has_point(point):
			continue
		if clearance(point) < CLEARANCE:
			continue
		var crowded := false
		for other: Vector2 in taken:
			crowded = crowded or other.distance_to(point) < MIN_SPACING
		if not crowded:
			return point
	return Vector2.INF


func _shuffle(items: Array) -> void:
	for index in range(items.size() - 1, 0, -1):
		var other := rng.randi_range(0, index)
		var held = items[index]
		items[index] = items[other]
		items[other] = held
