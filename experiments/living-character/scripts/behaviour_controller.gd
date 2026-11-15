extends Node
## Decides what the character does: which reaction fits his mood, what he
## gets up to when left alone. It composes routines from motor commands and
## hands them to the scheduler. It never touches scene nodes or dials.

const Config := preload("res://scripts/config.gd")

const HEAD := ["head", "face", "torso"]
const BOOK_ARM := "l"

var motor: Node
var scheduler: Node
var state: RefCounted
var stage: Node3D

var rng := RandomNumberGenerator.new()
var autonomous := false
var last_choice := "none"
var seed_value := 0

var _clock := 0.0
var _idle_wait := 2.0
var _noise_wait := 5.0
var _last_idle := ""
var _last_noise := "left"
var _grasp_failed := false


func setup(p_motor: Node, p_scheduler: Node, p_state: RefCounted, p_stage: Node3D, p_seed: int) -> void:
	motor = p_motor
	scheduler = p_scheduler
	state = p_state
	stage = p_stage
	seed_value = p_seed
	reset()


func reset() -> void:
	# Deterministic test mode: the same seed gives the same autonomous run.
	if seed_value != 0:
		rng.seed = seed_value
	else:
		rng.randomize()
	_clock = 0.0
	_idle_wait = 2.0
	_noise_wait = 5.0
	_last_idle = ""
	last_choice = "none"
	_grasp_failed = false


func set_autonomous(on: bool) -> void:
	autonomous = on
	_idle_wait = 1.5
	_noise_wait = rng.randf_range(4.0, 8.0)


func _process(delta: float) -> void:
	_clock += delta
	state.tick(delta, _clock, scheduler.is_busy())
	if not autonomous:
		return
	_noise_wait -= delta
	if _noise_wait <= 0.0:
		_noise_wait = rng.randf_range(9.0, 28.0)
		var roll := rng.randf()
		disturbance("left" if roll < 0.6 else ("right" if roll < 0.85 else "viewer"))
	if scheduler.is_busy():
		return
	_idle_wait -= delta
	if _idle_wait <= 0.0:
		_idle_wait = rng.randf_range(2.5, 7.0)
		_start(_pick_idle())


# ---------------------------------------------------------------- events

## A noise from a named place. The reaction depends on his state, unless a mood is forced.
func disturbance(point_name: String, forced_mood := "") -> void:
	_last_noise = point_name
	stage.flash_noise(point_name)
	var mood: String = state.register_stimulus(_clock)
	if forced_mood != "":
		mood = forced_mood
		state.mood = mood
	var where: Vector3 = stage.NOISE_POINTS[point_name]
	match mood:
		"irritated":
			_start(_react_irritated(where, point_name))
		"tired":
			_start(_react_tired(where, point_name))
		_:
			_start(_react_curious(where, point_name))


func read_book() -> void:
	_start(_book_action())


func _start(action: Dictionary) -> void:
	if scheduler.request(action):
		last_choice = action.name


# ---------------------------------------------------------------- reactions

func _reaction(action_name: String, steps: Array, fatigue: float) -> Dictionary:
	return {
		"name": action_name, "resources": HEAD, "priority": 2, "interruptible": true,
		"steps": steps,
		"on_end": func(completed: bool) -> Variant:
			state.attention = "nothing"
			state.activity = "dozing"
			if completed:
				state.add_fatigue(fatigue)
			return null,
	}


## First time: jolted awake, quick look, leans in with interest, settles.
func _react_curious(where: Vector3, source: String) -> Dictionary:
	var st: Dictionary = motor.style("calm")
	return _reaction("curious look (" + source + ")", [
		func() -> float:
			state.activity = "startled"
			motor.express("startled", st.intensity, 0.07)
			motor.shoulders([[0.04, 0.09, Tween.TRANS_QUAD, Tween.EASE_OUT], [0.012, 0.35]])
			motor.lean(-0.07, 0.0, 0.12)
			motor.turn_head(0.0, motor.style({"speed": 2.2}), 4.0)
			motor.breathe(2.0, 0.2)
			return 0.3,
		func() -> float:
			state.attention = "noise " + source
			state.activity = "looking"
			return motor.look_at(where, st),
		func() -> float:
			motor.express("curious", st.intensity, 0.35)
			motor.lean(0.11, signf(where.x) * 0.05, 0.6)
			return st.gaze_dwell * 0.55,
		func() -> float:
			motor.blink()
			return st.gaze_dwell * 0.45,
		func() -> float:
			motor.shoulders([[0.0, 0.5]])
			motor.express("neutral", 1.0, 0.5)
			return motor.look_at(stage.NOISE_POINTS["viewer"], motor.style({"speed": 0.8, "head_tilt": 0.0})) + 0.4,
		func() -> float:
			state.activity = "settling"
			motor.breathe(1.0, 2.0)
			return motor.return_to_rest(motor.style({"speed": 0.8})) + 0.2,
	], Config.FATIGUE_PER_REACTION)


## Again: stays put, rolls his eyes, snaps round to glare, huffs, turns away.
func _react_irritated(where: Vector3, source: String) -> Dictionary:
	var st: Dictionary = motor.style("irritated")
	var toward := signf(where.x)
	return _reaction("irritated glare (" + source + ")", [
		func() -> float:
			state.activity = "bristling"
			# Not startled: the face tightens before anything else moves.
			motor.express("irritated", 0.7, 0.3)
			motor.set_lids(0.88, 0.3)
			motor.shoulders([[0.03, 0.25]])
			motor.breathe(1.6, 0.3)
			return 0.75,
		func() -> float:
			motor.express("irritated", st.intensity, 0.2)
			return motor.eye_roll(toward, 0.75) + 0.1,
		func() -> float:
			state.attention = "noise " + source
			state.activity = "glaring"
			motor.lean(0.05, 0.0, 0.2)
			return motor.look_at(where, st),
		func() -> float:
			return st.gaze_dwell,
		func() -> float:
			# Huff: shoulders jump and drop, a short shake of the head.
			motor.shoulders([[0.05, 0.1, Tween.TRANS_QUAD, Tween.EASE_OUT], [-0.01, 0.25]])
			motor.shake_head(0.09)
			return 0.6,
		func() -> float:
			state.activity = "dismissing"
			# Turns pointedly away, past centre, and shuts his eyes on it.
			motor.set_lids(1.0, 0.5)
			return motor.turn_head(-toward * 16.0, motor.style({"speed": 0.45, "head_tilt": 6.0}), 6.0) + 0.5,
		func() -> float:
			motor.breathe(1.0, 2.5)
			return motor.return_to_rest(motor.style({"speed": 0.4}), false) + 0.1,
		func() -> float:
			return motor.express("asleep", 1.0, 1.2),
	], Config.FATIGUE_PER_REACTION * 1.3)


## Worn out: one eye half opens, the eyes drift over, he sags and gives up.
func _react_tired(where: Vector3, source: String) -> Dictionary:
	var st: Dictionary = motor.style("tired")
	return _reaction("tired glance (" + source + ")", [
		func() -> float:
			state.activity = "stirring"
			motor.express("tired_peek", st.intensity, 0.9)
			return 1.0,
		func() -> float:
			state.attention = "noise " + source
			state.activity = "glancing"
			return motor.look_at(where, st),
		func() -> float:
			motor.shoulders([[-0.03, 1.2]])
			motor.lean(0.07, 0.0, 1.4)
			return st.gaze_dwell,
		func() -> float:
			state.activity = "sighing"
			motor.shoulders([[0.03, 1.0], [-0.045, 1.5]])
			motor.express("tired", st.intensity, 1.2)
			return 2.2,
		func() -> float:
			state.activity = "sinking back"
			motor.turn_head(0.0, motor.style({"speed": 0.35, "head_tilt": 0.0}), -30.0)
			return motor.express("asleep", 1.0, 1.4) + 0.4,
		func() -> float:
			return motor.return_to_rest(motor.style({"speed": 0.35})) + 0.1,
	], Config.FATIGUE_PER_REACTION * 0.5)


# ---------------------------------------------------------------- the book

func _book_action() -> Dictionary:
	var st: Dictionary = motor.style("task")
	var book: Node3D = stage.book
	_grasp_failed = false
	var steps: Array = [
		func() -> float:
			state.activity = "waking"
			motor.breathe(1.2, 1.0)
			return motor.express("neutral", 1.0, 0.6),
		func() -> float:
			state.attention = "book"
			state.activity = "eyeing the book"
			return motor.look_at(book.global_position, st) + st.gaze_dwell,
		func() -> float:
			state.activity = "reaching"
			return motor.reach(motor.grip_point(book) + Vector3(0, 0.08, 0), BOOK_ARM, st),
		func() -> float:
			return motor.reach(motor.grip_point(book), BOOK_ARM, motor.style({"speed": 1.8})) + 0.1,
		func() -> float:
			if not motor.grasp(book, BOOK_ARM):
				_grasp_failed = true
				return -1.0
			state.activity = "holding the book"
			return 0.25,
		func() -> float:
			return motor.reach(motor.hand_target_for(book, book.global_position + Vector3(0, 0.09, 0)), BOOK_ARM, motor.style({"speed": 1.5})),
		func() -> float:
			var reading: Vector3 = motor.anchor("reading")
			motor.express("content", 1.0, 0.8)
			motor.tilt_grip(-0.95, BOOK_ARM, 0.8, 0.3)
			motor.look_at(reading, motor.style({"speed": 0.6, "head_share": 0.8, "head_tilt": 0.0, "shoulder_follow": 0.0}))
			return motor.reach(motor.hand_target_for(book, reading), BOOK_ARM, st) + 0.3,
	]
	# Reading: the head stays on the book while the eyes travel across the
	# page and flick back, a few times.
	for line in 3:
		steps.append(func() -> float:
			state.activity = "reading"
			if line == 1:
				motor.blink()
			return motor.scan_eyes(0.16, -0.16, 1.25) + 0.1)
	steps.append_array(_put_back_steps())
	return {
		"name": "read the book", "resources": HEAD + ["arm_l", "prop"], "priority": 1, "interruptible": true,
		"steps": steps,
		"on_end": _book_ended,
	}


func _put_back_steps() -> Array:
	var st: Dictionary = motor.style("task")
	var book: Node3D = stage.book
	return [
		func() -> float:
			state.attention = "table"
			state.activity = "putting the book back"
			motor.express("neutral", 1.0, 0.5)
			motor.tilt_grip(0.0, BOOK_ARM, 0.6)
			motor.look_at(stage.book_home(), st)
			return motor.reach(motor.hand_target_for(book, stage.book_home() + Vector3(0, 0.08, 0)), BOOK_ARM, st),
		func() -> float:
			return motor.reach(motor.hand_target_for(book, stage.book_home()), BOOK_ARM, motor.style({"speed": 1.6})) + 0.1,
		func() -> float:
			return motor.release(book, stage, stage.book_home(), BOOK_ARM),
		func() -> float:
			return motor.reach(motor.hand_position(BOOK_ARM) + Vector3(0, 0.07, 0), BOOK_ARM, motor.style({"speed": 2.0})),
		func() -> float:
			state.activity = "settling"
			motor.breathe(1.0, 2.0)
			return motor.return_to_rest(motor.style({"speed": 0.7})) + 0.2,
	]


## Called when the book routine finishes or is cut short. If he was
## interrupted with the book in his hand, he must still put it back.
func _book_ended(completed: bool) -> Variant:
	state.attention = "nothing"
	state.activity = "dozing"
	if completed:
		state.add_fatigue(Config.FATIGUE_PER_TASK)
		return null
	if motor.is_holding(BOOK_ARM):
		return {
			"name": "put the book back", "resources": HEAD + ["arm_l", "prop"], "priority": 1, "interruptible": false,
			"steps": _put_back_steps(), "on_end": func(_done: bool) -> Variant:
				state.attention = "nothing"
				state.activity = "dozing"
				return null,
		}
	if _grasp_failed:
		# Could not get hold of it: a small shrug, then back to rest.
		_grasp_failed = false
		return {
			"name": "give up on the book", "resources": HEAD + ["arm_l", "prop"], "priority": 1, "interruptible": true,
			"steps": [
				func() -> float:
					motor.express("tired", 0.8, 0.4)
					return motor.shoulders([[0.035, 0.25], [0.0, 0.5]]),
				func() -> float:
					return motor.return_to_rest(motor.style({"speed": 0.7})) + 0.2,
			],
		}
	return null


# ---------------------------------------------------------------- idles

func _idle(action_name: String, resources: Array, steps: Array) -> Dictionary:
	return {"name": action_name, "resources": resources, "priority": 0, "interruptible": true, "steps": steps,
		"on_end": func(_done: bool) -> Variant:
			state.attention = "nothing"
			state.activity = "dozing"
			return null}


## Picks something to do unprompted, weighted by mood and fatigue, never the
## same thing twice running.
func _pick_idle() -> Dictionary:
	var options := {"nod off": 2.0, "sigh and shift": 1.5}
	match state.mood:
		"calm":
			options["look around"] = 3.0
			if state.fatigue < 0.45:
				options["read the book"] = 2.5
		"irritated":
			options["suspicious peek"] = 4.0
			options["sigh and shift"] = 2.5
		"tired":
			options["nod off"] = 4.0
			options["sigh and shift"] = 3.0
	options.erase(_last_idle)
	var total := 0.0
	for weight: float in options.values():
		total += weight
	var pick := rng.randf() * total
	var choice: String = options.keys()[0]
	for option: String in options:
		pick -= options[option]
		if pick <= 0.0:
			choice = option
			break
	_last_idle = choice
	match choice:
		"read the book":
			return _book_action()
		"look around":
			return _idle_look_around()
		"suspicious peek":
			return _idle_suspicious_peek()
		"sigh and shift":
			return _idle_sigh()
		_:
			return _idle_nod_off()


func _idle_look_around() -> Dictionary:
	var names := ["viewer", "right", "left", "book"]
	var first: String = names[rng.randi_range(0, names.size() - 1)]
	var second: String = names[rng.randi_range(0, names.size() - 1)]
	var st: Dictionary = motor.style({"speed": 0.8})
	return _idle("look around", HEAD, [
		func() -> float:
			state.activity = "waking"
			return motor.express("neutral", 1.0, 0.7),
		func() -> float:
			state.attention = first
			state.activity = "looking around"
			return motor.look_at(_point(first), st) + rng.randf_range(0.8, 1.6),
		func() -> float:
			motor.blink()
			state.attention = second
			return motor.look_at(_point(second), st) + rng.randf_range(0.6, 1.4),
		func() -> float:
			return motor.return_to_rest(motor.style({"speed": 0.6})) + 0.3,
	])


func _idle_suspicious_peek() -> Dictionary:
	var where: Vector3 = stage.NOISE_POINTS[_last_noise]
	return _idle("suspicious peek", HEAD, [
		func() -> float:
			state.attention = "noise " + _last_noise
			state.activity = "peeking"
			motor.express("irritated", 0.8, 0.5)
			return motor.look_at(where, motor.style({"speed": 0.6, "head_share": 0.3, "head_tilt": 0.0})) + 1.2,
		func() -> float:
			return motor.return_to_rest(motor.style({"speed": 0.5})) + 0.3,
	])


func _idle_sigh() -> Dictionary:
	var side := 1.0 if rng.randf() < 0.5 else -1.0
	return _idle("sigh and shift", ["torso"], [
		func() -> float:
			state.activity = "shifting"
			motor.lean(0.03, side * 0.07, 1.2)
			return motor.shoulders([[0.03, 0.9], [-0.02, 1.2], [0.0, 0.8]]),
		func() -> float:
			return motor.lean(0.0, 0.0, 1.4),
	])


func _idle_nod_off() -> Dictionary:
	return _idle("nod off", ["head"], [
		func() -> float:
			state.activity = "nodding off"
			return motor.turn_head(0.0, motor.style({"speed": 0.3, "head_tilt": 0.0}), -34.0) + 0.3,
		func() -> float:
			# The jerk back up of someone catching themselves.
			return motor.turn_head(0.0, motor.style({"speed": 2.2, "head_tilt": 0.0}), -8.0) + 0.5,
		func() -> float:
			return motor.return_to_rest(motor.style({"speed": 0.4})) + 0.2,
	])


func _point(point_name: String) -> Vector3:
	if point_name == "book":
		return stage.book.global_position
	return stage.NOISE_POINTS[point_name]
