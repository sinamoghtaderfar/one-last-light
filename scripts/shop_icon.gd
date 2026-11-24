class_name ShopIcon
extends Control
## A shop item's pictogram; grey while the item cannot be bought.

var kind: int = 0
var active: bool = true:
	set(value):
		active = value
		queue_redraw()


func _init(item_kind: int = 0) -> void:
	kind = item_kind
	custom_minimum_size = Vector2(48, 44)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	HudIcons.shop_item(self, kind, size * 0.5, 40.0, HudIcons.TEAL if active else HudIcons.MUTED)
