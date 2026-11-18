class_name LevelDefinition
extends Resource
## Everything one level needs. The game manager builds the level from this and nothing else.

## How the upgrade offers of a finished level are presented.
enum OfferScreen {
	NONE, ## No upgrade is on offer. The level-complete panel only has Continue.
	POPUP, ## Offered inside the level-complete panel.
	PREPARE, ## Offered on a "prepare for the next level" screen shown after level complete.
}

@export_range(1, 99) var level_number: int = 1
@export var title: String = ""
@export var survivors: Array[SurvivorSpec] = []
@export_range(10.0, 900.0) var time_limit: float = 240.0
## Survivors that may be lost while the level is still a success. Zero: everyone must be delivered.
@export_range(0, 98) var allowed_losses: int = 0
@export var show_mouse_cue: bool = false
@export var offer_screen: OfferScreen = OfferScreen.NONE
@export var upgrade_offers: Array[UpgradeOffer] = []
## When true, buying one offer of this level locks the others.
@export var offers_exclusive: bool = false


func survivor_count() -> int:
	return survivors.size()


## Every delivery the level needs for success.
func required_deliveries() -> int:
	return survivors.size() - allowed_losses


func offer_by_id(offer_id: StringName) -> UpgradeOffer:
	for offer in upgrade_offers:
		if offer.id == offer_id:
			return offer
	return null
