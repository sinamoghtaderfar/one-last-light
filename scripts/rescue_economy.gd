class_name RescueEconomy
extends Resource
## The campaign's currency and what it buys. Each level is rated 1-3 stars; a star is worth
## points only the first time it is earned. Replaying a level for the same rating pays nothing;
## improving it pays the difference. Points buy shop items (see ShopCatalog). Everything persists
## across levels and replays and is reset only by reset_campaign().

## Light Points a level is worth at 0, 1, 2 and 3 stars.
@export var points_for_stars: Array[int] = [0, 50, 100, 200]
@export_range(1, 12) var starting_capacity: int = 1

var points: int = 0
var total_points_earned: int = 0
var total_rescued: int = 0
## Best rating per level number.
var best_stars: Dictionary = {}
## Item id -> true for every item bought.
var owned: Dictionary = {}
## Items bought whose effect has not been shown to the player yet (shown at the next level start).
var unshown: Array[String] = []
var boost_used: bool = false
## One entry per purchase: {id, price, after_level}.
var purchases: Array[Dictionary] = []

var capacity: int:
	get: return starting_capacity + _count(ShopCatalog.Kind.CAPACITY)
var speed_level: int:
	get: return _count(ShopCatalog.Kind.SPEED)
var light_level: int:
	get: return _count(ShopCatalog.Kind.LIGHT)
var has_boost: bool:
	get: return owned.has("boost") and not boost_used


func _init() -> void:
	resource_local_to_scene = true


func reset_campaign() -> void:
	points = 0
	total_points_earned = 0
	total_rescued = 0
	best_stars.clear()
	owned.clear()
	unshown.clear()
	boost_used = false
	purchases.clear()


func total_stars() -> int:
	var sum := 0
	for value in best_stars.values():
		sum += value
	return sum


func points_for(stars: int) -> int:
	return points_for_stars[clampi(stars, 0, points_for_stars.size() - 1)]


## Called once when a level is won. Returns the points paid (only for stars not earned before).
func commit_level(level_number: int, stars: int, delivered: int) -> int:
	var before: int = best_stars.get(level_number, 0)
	var gained := maxi(points_for(stars) - points_for(before), 0)
	best_stars[level_number] = maxi(stars, before)
	points += gained
	total_points_earned += gained
	total_rescued += delivered
	return gained


## Why an item can or cannot be bought right now, for the shop UI:
## "owned", "level" (unlocks later), "requires" (first phase missing), "points" (too expensive) or "".
## next_level is the level the player is about to play.
func status(id: String, next_level: int) -> String:
	var entry := ShopCatalog.item(id)
	if entry.is_empty():
		return "level"
	if owned.has(id):
		return "owned"
	if next_level < int(entry["unlock_level"]):
		return "level"
	if entry["requires"] != "" and not owned.has(entry["requires"]):
		return "requires"
	if points < int(entry["price"]):
		return "points"
	return ""


func purchase(id: String, next_level: int) -> bool:
	if status(id, next_level) != "":
		return false
	var entry := ShopCatalog.item(id)
	points -= int(entry["price"])
	owned[id] = true
	if entry["kind"] != ShopCatalog.Kind.BOOST:
		unshown.append(id)
	purchases.append({"id": id, "price": entry["price"], "after_level": next_level - 1})
	return true


func use_boost() -> bool:
	if not has_boost:
		return false
	boost_used = true
	return true


func _count(kind: ShopCatalog.Kind) -> int:
	var count := 0
	for id in owned:
		if ShopCatalog.item(id).get("kind", -1) == kind:
			count += 1
	return count
