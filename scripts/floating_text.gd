class_name FloatingText
extends Node2D
## A short speech bubble ("Got you!", "Bye!") that rises from the boat and fades, then frees itself.

const DURATION := 1.4

var text: String = ""
var color: Color = Color.WHITE
var elapsed: float = 0.0


func _init(content: String = "", tint: Color = Color.WHITE) -> void:
	text = content
	color = tint
	z_index = 30


func _process(delta: float) -> void:
	elapsed += delta
	position.y -= 22.0 * delta
	if elapsed >= DURATION:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var alpha := 1.0 - smoothstep(DURATION * 0.6, DURATION, elapsed)
	var pop := 1.0 + 0.25 * (1.0 - smoothstep(0.0, 0.18, elapsed))
	var font := ThemeDB.fallback_font
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x + 20.0
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE * pop)
	var bubble := StyleBoxFlat.new()
	bubble.bg_color = Color(0.05, 0.11, 0.16, 0.9 * alpha)
	bubble.border_color = Color(color, alpha)
	bubble.set_border_width_all(2)
	bubble.set_corner_radius_all(10)
	draw_style_box(bubble, Rect2(Vector2(-width * 0.5, -14), Vector2(width, 26)))
	draw_colored_polygon(PackedVector2Array([Vector2(-6, 12), Vector2(6, 12), Vector2(0, 19)]), Color(color, alpha))
	draw_string(font, Vector2(-width * 0.5, 5), text, HORIZONTAL_ALIGNMENT_CENTER, width, 16, Color(color, alpha))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
