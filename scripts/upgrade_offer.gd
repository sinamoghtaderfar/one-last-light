class_name UpgradeOffer
extends Resource
## One purchasable boat upgrade. Prices live here, in the level files, and nowhere else.

enum Kind { CAPACITY, SPEED }

## Unique across the campaign. The economy remembers claimed ids, so an offer is bought at most once.
@export var id: StringName = &""
@export var kind: Kind = Kind.CAPACITY
@export_range(0, 100) var cost: int = 3
## Seats added (CAPACITY) or speed levels added (SPEED).
@export_range(1, 4) var amount: int = 1
