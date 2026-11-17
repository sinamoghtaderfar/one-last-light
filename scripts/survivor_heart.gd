class_name SurvivorHeart
extends Control
## One heart in the top HUD. It mirrors exactly one Survivor and never simulates oxygen itself:
## the fill, colour, pulse and animations are all derived from the survivor's own state and
## oxygen fields every frame. advance() is public so tests can step it by hand.

const ACTIVE_COLOR := Color("87dfa3") # Same palette as the oxygen label on the map.
const WARNING_COLOR := Color("ffdc70")
const CRITICAL_COLOR := Color("fa877a")
const SECURED_COLOR := Color("7fe0cc")
const LOST_FILL := Color("6e2b33")
const LOST_OUTLINE := Color("d1565e")
const HOLLOW := Color("0d1c29")
const OUTLINE := Color("6d8998")
const ID_COLOR := Color("91abb7")

## Colours ease over this many seconds of oxygen above each warning level, so a heart never pops.
const BLEND_SECONDS := 12.0
const BOARD_DURATION := 0.40
const DELIVER_DURATION := 0.60
const LOST_DURATION := 0.60
const LOST_SCALE := 0.86
const PULSE_HZ := 1.4
const PULSE_AMOUNT := 0.08

static var _unit_shape := PackedVector2Array()

var survivor: Survivor
## The state the heart is currently showing (it follows survivor.state).
var shown_state: Survivor.State = Survivor.State.ACTIVE
## 0..1 share of the heart that is filled. Mirrors oxygen_remaining / oxygen_duration.
var fill_ratio: float = 1.0
## Seconds into the current transition animation, or -1.0 when none is playing.
var animation_elapsed: float = -1.0
var show_id: bool = true

var _pulse_time: float = 0.0
var _shape := PackedVector2Array()
var _drawn_signature := ""


func _init() -> void:
	custom_minimum_size = Vector2(24, 24)
	size = Vector2(24, 24)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	_rebuild_shape()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_rebuild_shape()


func _process(delta: float) -> void:
	advance(delta)


func bind(person: Survivor) -> void:
	survivor = person
	shown_state = person.state
	animation_elapsed = -1.0
	_pulse_time = 0.0
	_sync_fill()
	queue_redraw()


## Follows the survivor and moves any transition animation forward by delta.
func advance(delta: float) -> void:
	if survivor == null:
		return
	if survivor.state != shown_state:
		_enter_state(survivor.state)
	_pulse_time += delta
	if animation_elapsed >= 0.0:
		animation_elapsed += delta
		if animation_elapsed >= _animation_length():
			animation_elapsed = -1.0
	_sync_fill()
	var signature := _signature()
	if signature != _drawn_signature:
		_drawn_signature = signature
		queue_redraw()


func is_critical() -> bool:
	return survivor != null and shown_state == Survivor.State.ACTIVE and survivor.oxygen_remaining <= Survivor.CRITICAL_SECONDS


## True only while this survivor's oxygen is really running. Before launch, during the countdown and
## while paused it is not, so a heart never pulses as if the game were live.
func is_pulsing() -> bool:
	return is_critical() and survivor.is_processing() and survivor.can_process()


func is_aboard() -> bool:
	return shown_state == Survivor.State.ON_MAIN_BOAT or shown_state == Survivor.State.ON_EMERGENCY_BOAT


func is_animating() -> bool:
	return animation_elapsed >= 0.0


## The colour of the filled part (or of the whole heart once it is delivered or lost).
func fill_color() -> Color:
	match shown_state:
		Survivor.State.ON_MAIN_BOAT, Survivor.State.ON_EMERGENCY_BOAT, Survivor.State.DELIVERED:
			return SECURED_COLOR
		Survivor.State.LOST:
			return LOST_FILL
	return oxygen_color(survivor.oxygen_remaining if survivor != null else 999.0)


## Green while comfortable, amber from the warning level, red from the critical level.
static func oxygen_color(seconds: float) -> Color:
	var warning := Survivor.WARNING_SECONDS
	var critical := Survivor.CRITICAL_SECONDS
	if seconds <= critical:
		return CRITICAL_COLOR
	if seconds <= critical + BLEND_SECONDS:
		return CRITICAL_COLOR.lerp(WARNING_COLOR, (seconds - critical) / BLEND_SECONDS)
	if seconds <= warning:
		return WARNING_COLOR
	if seconds <= warning + BLEND_SECONDS:
		return WARNING_COLOR.lerp(ACTIVE_COLOR, (seconds - warning) / BLEND_SECONDS)
	return ACTIVE_COLOR


## Overall scale: the transition animations and, only when critical, the warning pulse.
func visual_scale() -> float:
	var scale_now := 1.0
	var progress := _animation_progress()
	match shown_state:
		Survivor.State.ON_MAIN_BOAT, Survivor.State.ON_EMERGENCY_BOAT:
			if progress >= 0.0:
				scale_now = 1.0 + 0.30 * sin(progress * PI)
		Survivor.State.DELIVERED:
			if progress >= 0.0:
				scale_now = 1.0 + 0.38 * sin(progress * PI)
		Survivor.State.LOST:
			scale_now = LOST_SCALE if progress < 0.0 else lerpf(1.12, LOST_SCALE, ease(progress, 0.4))
	if is_pulsing():
		scale_now *= 1.0 + PULSE_AMOUNT * (0.5 - 0.5 * cos(_pulse_time * TAU * PULSE_HZ))
	return scale_now


func visual_offset() -> Vector2:
	var progress := _animation_progress()
	if shown_state == Survivor.State.LOST and progress >= 0.0:
		return Vector2(sin(animation_elapsed * 70.0) * 2.6 * (1.0 - progress), 0.0)
	return Vector2.ZERO


func visual_alpha() -> float:
	if shown_state == Survivor.State.LOST:
		var progress := _animation_progress()
		return 0.82 if progress < 0.0 else lerpf(1.0, 0.82, progress)
	return 1.0


# --- internals ------------------------------------------------------------------------------

func _enter_state(new_state: Survivor.State) -> void:
	var previous := shown_state
	shown_state = new_state
	match new_state:
		Survivor.State.ACTIVE:
			animation_elapsed = -1.0 # A replay reset snaps back; no celebration.
			_pulse_time = 0.0
		_:
			animation_elapsed = 0.0 if previous != new_state else -1.0


func _sync_fill() -> void:
	match shown_state:
		Survivor.State.DELIVERED:
			fill_ratio = 1.0
		Survivor.State.LOST:
			fill_ratio = 0.0
		_:
			# Active hearts drain with the oxygen. Aboard hearts hold the level it was frozen at.
			fill_ratio = clampf(survivor.oxygen_remaining / maxf(survivor.oxygen_duration, 0.01), 0.0, 1.0)


func _animation_length() -> float:
	match shown_state:
		Survivor.State.DELIVERED:
			return DELIVER_DURATION
		Survivor.State.LOST:
			return LOST_DURATION
	return BOARD_DURATION


func _animation_progress() -> float:
	if animation_elapsed < 0.0:
		return -1.0
	return clampf(animation_elapsed / _animation_length(), 0.0, 1.0)


func _signature() -> String:
	var pulsing := is_pulsing()
	return "%d|%.4f|%.3f|%d|%.3f" % [shown_state, fill_ratio, animation_elapsed, int(pulsing), _pulse_time if pulsing else 0.0]


static func _unit_heart() -> PackedVector2Array:
	if _unit_shape.is_empty():
		var raw := PackedVector2Array()
		for step in range(48):
			var angle := TAU * step / 48.0
			raw.append(Vector2(
				16.0 * pow(sin(angle), 3.0),
				-(13.0 * cos(angle) - 5.0 * cos(2.0 * angle) - 2.0 * cos(3.0 * angle) - cos(4.0 * angle))))
		var low := raw[0]
		var high := raw[0]
		for point in raw:
			low = Vector2(minf(low.x, point.x), minf(low.y, point.y))
			high = Vector2(maxf(high.x, point.x), maxf(high.y, point.y))
		for point in raw:
			_unit_shape.append((point - low) / (high - low))
	return _unit_shape


## The heart outline centred on the origin, sized to fill this control.
func _rebuild_shape() -> void:
	_shape = PackedVector2Array()
	for point in _unit_heart():
		_shape.append((point - Vector2(0.5, 0.5)) * size)
	_drawn_signature = ""
	queue_redraw()


func _closed(points: PackedVector2Array) -> PackedVector2Array:
	var loop := points.duplicate()
	loop.append(points[0])
	return loop


func _draw() -> void:
	if survivor == null or _shape.is_empty():
		return
	var alpha := visual_alpha()
	draw_set_transform(size * 0.5 + visual_offset(), 0.0, Vector2.ONE * visual_scale())
	var half := size * 0.5
	var progress := _animation_progress()
	match shown_state:
		Survivor.State.ACTIVE:
			draw_colored_polygon(_shape, Color(HOLLOW, alpha))
			_draw_fill(Color(fill_color(), alpha))
			draw_polyline(_closed(_shape), Color(fill_color().lerp(OUTLINE, 0.45), alpha), 1.4, true)
		Survivor.State.ON_MAIN_BOAT, Survivor.State.ON_EMERGENCY_BOAT:
			draw_colored_polygon(_shape, HOLLOW)
			_draw_fill(Color(SECURED_COLOR, 0.38))
			draw_polyline(_closed(_shape), SECURED_COLOR, 2.4, true)
		Survivor.State.DELIVERED:
			draw_colored_polygon(_shape, SECURED_COLOR)
			draw_polyline(_closed(_shape), Color(1, 1, 1, 0.85), 1.4, true)
			var check := PackedVector2Array([Vector2(-0.24, 0.0) * size, Vector2(-0.07, 0.17) * size, Vector2(0.25, -0.17) * size])
			draw_polyline(check, HOLLOW, 2.4, true)
			if progress >= 0.0:
				draw_arc(Vector2.ZERO, half.x * (0.9 + progress * 0.8), 0.0, TAU, 28, Color(SECURED_COLOR, (1.0 - progress) * 0.8), 1.6, true)
		Survivor.State.LOST:
			draw_colored_polygon(_shape, Color(LOST_FILL, alpha))
			draw_polyline(_closed(_shape), Color(LOST_OUTLINE, alpha), 1.4, true)
			var crack := PackedVector2Array([
				Vector2(-0.02, -0.46) * size, Vector2(-0.12, -0.20) * size, Vector2(0.10, -0.02) * size,
				Vector2(-0.08, 0.20) * size, Vector2(0.04, 0.48) * size])
			draw_polyline(crack, Color(HOLLOW, 0.95), 2.2, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if show_id:
		var id_color := ID_COLOR
		if shown_state == Survivor.State.LOST:
			id_color = LOST_OUTLINE
		elif shown_state == Survivor.State.DELIVERED or is_aboard():
			id_color = SECURED_COLOR
		draw_string(ThemeDB.fallback_font, Vector2(-4, size.y + 11), "%02d" % survivor.survivor_id,
			HORIZONTAL_ALIGNMENT_CENTER, size.x + 8, 9, id_color)


## Fills the heart from the bottom up to fill_ratio of its height.
func _draw_fill(color: Color) -> void:
	if fill_ratio <= 0.002:
		return
	if fill_ratio >= 0.998:
		draw_colored_polygon(_shape, color)
		return
	var top := size.y * 0.5 - fill_ratio * size.y
	var band := PackedVector2Array([
		Vector2(-size.x, top), Vector2(size.x, top), Vector2(size.x, size.y), Vector2(-size.x, size.y)])
	for piece in Geometry2D.intersect_polygons(_shape, band):
		if piece.size() >= 3:
			draw_colored_polygon(piece, color)
