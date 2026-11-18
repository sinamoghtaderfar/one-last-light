class_name RescueEconomy
extends Resource
## The campaign's one currency and the boat upgrades it buys. It persists across levels and level
## replays, and is reset only by reset_campaign(). Stars a level earns stay pending until the level
## succeeds, so a failed attempt can never be replayed for extra stars.

@export_range(0, 100) var stars_per_survivor: int = 3
@export_range(1, 12) var starting_capacity: int = 1
@export_range(1, 12) var maximum_capacity: int = 4
@export_range(0, 10) var maximum_speed_level: int = 3

## Banked stars. They are what the player can spend.
var stars: int = 0
## Stars earned by deliveries in the level being played. Banked on success, dropped on failure.
var pending_stars: int = 0
var capacity: int = 1
var speed_level: int = 0
var total_stars_earned: int = 0
var total_rescued: int = 0
## One entry per purchase: {offer, kind, cost, level}.
var purchases: Array[Dictionary] = []
var _claimed: Dictionary = {}


func _init() -> void:
	resource_local_to_scene = true
	capacity = starting_capacity


func reset_campaign() -> void:
	stars = 0
	pending_stars = 0
	capacity = starting_capacity
	speed_level = 0
	total_stars_earned = 0
	total_rescued = 0
	purchases.clear()
	_claimed.clear()


## Bank plus the stars the running level has earned so far, which is what the HUD shows.
func visible_stars() -> int:
	return stars + pending_stars


func credit_delivery(count: int) -> int:
	var earned := maxi(count, 0) * stars_per_survivor
	pending_stars += earned
	return earned


## Called once when a level succeeds. Returns the stars that level paid.
func commit_level(delivered: int) -> int:
	var earned := pending_stars
	stars += earned
	total_stars_earned += earned
	total_rescued += delivered
	pending_stars = 0
	return earned


func discard_pending() -> void:
	pending_stars = 0


func is_claimed(offer: UpgradeOffer) -> bool:
	return _claimed.has(offer.id)


## The real values a purchase would produce, for the UI: {before, after, cost, available, reason}.
func preview(offer: UpgradeOffer) -> Dictionary:
	var before := capacity if offer.kind == UpgradeOffer.Kind.CAPACITY else speed_level
	var limit := maximum_capacity if offer.kind == UpgradeOffer.Kind.CAPACITY else maximum_speed_level
	var after := mini(before + offer.amount, limit)
	var reason := ""
	if is_claimed(offer):
		reason = "claimed"
	elif before >= limit:
		reason = "maximum"
	elif stars < offer.cost:
		reason = "stars"
	return {"before": before, "after": after, "cost": offer.cost, "available": reason == "", "reason": reason}


## Returns true only when stars were deducted and the upgrade applied. Never goes negative, never
## jumps past one step, and never applies the same offer twice.
func purchase(offer: UpgradeOffer, level_number: int = 0) -> bool:
	if offer == null:
		return false
	var quote := preview(offer)
	if not quote["available"]:
		return false
	stars -= offer.cost
	if offer.kind == UpgradeOffer.Kind.CAPACITY:
		capacity = quote["after"]
	else:
		speed_level = quote["after"]
	_claimed[offer.id] = true
	purchases.append({"offer": offer.id, "kind": offer.kind, "cost": offer.cost, "level": level_number})
	return true
