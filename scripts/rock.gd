class_name NavigationRock
extends StaticBody2D
## The exported radius controls both the navigation obstacle and its drawing.

@export var radius: float = 25.0


func _ready() -> void:
	collision_layer = 1
	collision_mask = 2
	var circle := CircleShape2D.new()
	circle.radius = radius
	$CollisionShape2D.shape = circle
	queue_redraw()


func _draw() -> void:
	draw_circle(Vector2.ZERO, radius + 4.0, Color(0.34, 0.54, 0.59, 0.14))
	var outline := PackedVector2Array()
	var factors: Array[float] = [0.92, 1.0, 0.94, 0.97, 0.91, 1.0, 0.96, 0.93]
	for corner in range(factors.size()):
		outline.append(Vector2.from_angle(corner * TAU / factors.size()) * radius * factors[corner])
	draw_colored_polygon(outline, Color("52646b"))
	outline.append(outline[0])
	draw_polyline(outline, Color("91a0a2"), 2.0, true)
	draw_line(Vector2(-radius * 0.39, -radius * 0.22),
		Vector2(radius * 0.12, -radius * 0.43), Color("72848a"), 2.0, true)
