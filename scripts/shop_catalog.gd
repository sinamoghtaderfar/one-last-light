class_name ShopCatalog
extends RefCounted
## Every item the shop sells, in display order. Prices are in Light Points.
## unlock_level: the first level the item can be used in. It can be bought from the shop at the end
## of the level before it (so "unlocks at Level 5" means "buyable after finishing Level 4").
## requires: an item that must be owned first (the second phase of an upgrade).
## Items whose unlock level is beyond the current campaign stay visible but locked.

enum Kind { CAPACITY, SPEED, LIGHT, DINGHY, BOOST }

const ITEMS := [
	{"id": "capacity_1", "kind": Kind.CAPACITY, "title": "Extra Seat", "detail": "Carry 2 survivors per trip.", "price": 300, "unlock_level": 4, "requires": ""},
	{"id": "speed_1", "kind": Kind.SPEED, "title": "Faster Engine", "detail": "Boat speed +18%.", "price": 300, "unlock_level": 5, "requires": ""},
	{"id": "boost", "kind": Kind.BOOST, "title": "Oxygen Boost", "detail": "Once: +15 s oxygen for everyone in the water.", "price": 400, "unlock_level": 5, "requires": ""},
	{"id": "light_1", "kind": Kind.LIGHT, "title": "Brighter Lighthouse", "detail": "Longer, wider beam.", "price": 200, "unlock_level": 6, "requires": ""},
	{"id": "dinghy", "kind": Kind.DINGHY, "title": "Rescue Dinghy", "detail": "Click a survivor: it fetches them on its own.", "price": 600, "unlock_level": 7, "requires": ""},
	{"id": "speed_2", "kind": Kind.SPEED, "title": "Turbo Engine", "detail": "Boat speed +18% more.", "price": 400, "unlock_level": 8, "requires": "speed_1"},
	{"id": "capacity_2", "kind": Kind.CAPACITY, "title": "Third Seat", "detail": "Carry 3 survivors per trip.", "price": 500, "unlock_level": 9, "requires": "capacity_1"},
	{"id": "light_2", "kind": Kind.LIGHT, "title": "Lighthouse Lens", "detail": "Even longer, wider beam.", "price": 300, "unlock_level": 10, "requires": "light_1"},
]


static func item(id: String) -> Dictionary:
	for entry in ITEMS:
		if entry["id"] == id:
			return entry
	return {}


static func title_of(id: String) -> String:
	var entry := item(id)
	return entry["title"] if not entry.is_empty() else id
