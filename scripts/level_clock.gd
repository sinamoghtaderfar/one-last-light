class_name LevelClock
extends RefCounted
## The game manager advances this clock only during an active rescue.

var duration: float
var remaining: float


func reset(seconds: float) -> void:
	duration = maxf(seconds, 0.0)
	remaining = duration


func advance(delta: float) -> void:
	remaining = maxf(remaining - delta, 0.0)


func elapsed() -> float:
	return duration - remaining
