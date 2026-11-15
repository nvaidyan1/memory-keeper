extends RefCounted
## What the character currently feels and remembers. No scene access.

const Config := preload("res://scripts/config.gd")

var mood := "calm"            # calm | irritated | tired
var fatigue := 0.0            # 0 rested .. 1 exhausted
var attention := "nothing"    # name of what he is attending to
var activity := "asleep"      # what the body is doing, for the overlay
var stimulus_times: Array[float] = []


func reset() -> void:
	mood = "calm"
	fatigue = 0.0
	attention = "nothing"
	activity = "asleep"
	stimulus_times.clear()


func recent_stimulus_count(now: float) -> int:
	while not stimulus_times.is_empty() and now - stimulus_times[0] > Config.STIMULUS_MEMORY:
		stimulus_times.pop_front()
	return stimulus_times.size()


## Records a disturbance and returns the mood it puts him in.
func register_stimulus(now: float) -> String:
	stimulus_times.append(now)
	var count := recent_stimulus_count(now)
	if fatigue >= Config.TIRED_ABOVE:
		mood = "tired"
	elif count >= 2:
		mood = "irritated"
	else:
		mood = "calm"
	return mood


func add_fatigue(amount: float) -> void:
	fatigue = clampf(fatigue + amount, 0.0, 1.0)


func tick(delta: float, now: float, busy: bool) -> void:
	if not busy:
		fatigue = maxf(0.0, fatigue - Config.FATIGUE_RECOVERY * delta)
		# Irritation fades once the noises are forgotten.
		if recent_stimulus_count(now) == 0 and mood == "irritated":
			mood = "calm"
		if fatigue < Config.TIRED_ABOVE * 0.6 and mood == "tired":
			mood = "calm"
