extends Node
## Decides what the character does: which reaction fits his mood, what he
## gets up to when left alone. It composes routines from motor commands and
## hands them to the scheduler. It never touches scene nodes or dials.
##
## Everything outside (keyboard, web remote, later a sensor) goes through
## command(): one entry point, so every input source behaves identically.

const Config := preload("res://scripts/config.gd")

const HEAD := ["head", "face", "torso", "arm_r"]
const BODY := ["head", "face", "torso", "arm_r", "arm_l", "prop"]
const BOOK_ARM := "l"

const COMMANDS := ["curious", "irritated", "tired", "read_book", "move_book", "frame_lifted", "toggle_auto", "reset"]

signal reset_requested

var motor: Node
var scheduler: Node
var state: RefCounted
var stage: Node3D

var rng := RandomNumberGenerator.new()
var autonomous := false
var last_choice := "none"
var last_command := "none"
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
		_idle_wait = rng.randf_range(3.0, 8.0)
		_start(_pick_idle())


# ---------------------------------------------------------------- commands

## The single entry point for outside input. Returns a short acknowledgement.
func command(command_name: String) -> String:
	var reply := ""
	match command_name:
		"curious":
			reply = disturbance("left", "calm")
		"irritated":
			reply = disturbance("left", "irritated")
		"tired":
			reply = disturbance("left", "tired")
		"read_book":
			reply = _start(_book_action())
		"move_book":
			if motor.is_holding(BOOK_ARM) or scheduler.owns("prop"):
				reply = "ignored: the book is in use"
			else:
				stage.slide_book_to_slot(1 - stage.book_slot)
				reply = "book moved to position %d" % stage.book_slot
		"frame_lifted":
			reply = frame_lifted()
		"toggle_auto":
			set_autonomous(not autonomous)
			reply = "autonomous %s" % ("on" if autonomous else "off")
		"reset":
			reset_requested.emit()
			reply = "reset"
		_:
			reply = "unknown command"
	last_command = "%s: %s" % [command_name, reply]
	return reply


## A noise from a named place. The reaction depends on his state, unless a mood is forced.
func disturbance(point_name: String, forced_mood := "") -> String:
	_last_noise = point_name
	stage.flash_noise(point_name)
	var mood: String = state.register_stimulus(_clock)
	if forced_mood != "":
		mood = forced_mood
		state.mood = mood
	var where: Vector3 = stage.point(point_name)
	match mood:
		"irritated":
			return _start(_react_irritated(where, point_name))
		"tired":
			return _start(_react_tired(where, point_name))
		_:
			return _start(_react_curious(where, point_name))


## The frame he lives in has been picked up or tilted. Independent of what
## detected it: a button today, a motion sensor later.
func frame_lifted() -> String:
	return _start(_frame_lifted_action())


func _start(action: Dictionary) -> String:
	var result: String = scheduler.request(action)
	if result != "dropped":
		last_choice = action.name
	return "%s, %s" % [action.name, result]


func _settled(_completed: bool) -> Variant:
	state.attention = "nothing"
	state.activity = "asleep"
	return null


# ---------------------------------------------------------------- reactions

func _reaction(action_name: String, steps: Array, fatigue: float) -> Dictionary:
	return {
		"name": action_name, "resources": HEAD, "priority": 2, "interruptible": true,
		"steps": steps,
		"on_end": func(completed: bool) -> Variant:
			if completed:
				state.add_fatigue(fatigue)
			return _settled(completed),
	}


## First time: bolts upright clutching the chair, whips round, cranes toward
## the sound with his whole body, checks with the viewer, eases back to sleep.
func _react_curious(where: Vector3, source: String) -> Dictionary:
	var st: Dictionary = motor.style("calm")
	var toward := signf(where.x)
	return _reaction("curious look (" + source + ")", [
		func() -> float:
			state.activity = "startled"
			motor.express("startled", 1.0, 0.07)
			motor.shoulders([[0.065, 0.09, Tween.TRANS_QUAD, Tween.EASE_OUT], [0.02, 0.4]])
			motor.tilt_shoulders(0.0, 0.15)
			motor.sink(-0.01, 0.12)
			motor.lean(0.04, 0.0, 0.14)
			motor.turn_head(0.0, motor.style({"speed": 2.4, "head_tilt": 0.0}), 6.0)
			motor.gesture(motor.anchor("arm_rest_r"), "r", 0.22, 0.05)
			motor.gesture(motor.anchor("arm_rest_l"), "l", 0.15, 0.01)
			motor.breathe(2.2, 0.2, 1.3)
			return 0.55,
		func() -> float:
			state.attention = "noise " + source
			state.activity = "looking"
			return motor.look_at(where, st) + 0.15,
		func() -> float:
			# Cranes toward it: torso follows the head, far shoulder comes up.
			motor.express("curious", 1.0, 0.35)
			motor.lean(0.20, toward * 0.13, 0.7)
			motor.tilt_shoulders(-toward * 0.10, 0.7)
			return st.gaze_dwell * 0.7,
		func() -> float:
			motor.blink()
			motor.tilt_head(-toward * 10.0, 0.35)
			return st.gaze_dwell * 0.5,
		func() -> float:
			# Checks with the viewer: did you hear that?
			motor.express("astonished", 0.7, 0.3)
			motor.lean(0.08, 0.0, 0.6)
			motor.tilt_shoulders(0.0, 0.6)
			return motor.look_at(stage.point("viewer"), motor.style({"speed": 1.0, "head_tilt": 0.0, "anticipation": 0.0})) + 0.9,
		func() -> float:
			motor.express("neutral", 1.0, 0.6)
			motor.shoulders([[0.0, 0.6]])
			return motor.look_at(where, motor.style({"speed": 0.7, "head_share": 0.4, "head_tilt": 0.0, "anticipation": 0.0})) + 0.5,
		func() -> float:
			state.activity = "settling"
			return motor.return_to_rest(motor.style({"speed": 0.5})) + 0.3,
	], Config.FATIGUE_PER_REACTION)


## Again: refuses to open his eyes, swells with annoyance, rolls his eyes,
## snaps round to glare, flings a hand at the noise, turns his back on it.
func _react_irritated(where: Vector3, source: String) -> Dictionary:
	var st: Dictionary = motor.style("irritated")
	var toward := signf(where.x)
	var wave_side := "r" if toward < 0.0 else "l"
	return _reaction("irritated glare (" + source + ")", [
		func() -> float:
			state.activity = "bristling"
			# Eyes stay shut; the face clenches and the chest swells.
			motor.express("irritated", 1.0, 0.25)
			motor.set_lids(1.0, 0.1)
			motor.shoulders([[0.05, 0.9]])
			motor.sink(0.0, 0.9)
			motor.lean(-0.04, 0.0, 0.9)
			motor.turn_head(8.0, motor.style({"speed": 0.5, "head_tilt": 0.0}), 4.0)
			motor.breathe(1.6, 0.3, 1.2)
			return 1.1,
		func() -> float:
			motor.express("irritated", st.intensity, 0.2)
			return motor.eye_roll(toward, 0.8) + 0.15,
		func() -> float:
			state.attention = "noise " + source
			state.activity = "glaring"
			motor.lean(0.07, toward * 0.05, 0.18)
			motor.tilt_shoulders(toward * 0.08, 0.2)
			return motor.look_at(where, st),
		func() -> float:
			return st.gaze_dwell,
		func() -> float:
			# "Bah!": a hand flung at the noise, a shake of the head.
			state.activity = "dismissing"
			motor.gesture(motor.anchor("wave_" + wave_side), wave_side, 0.22, 0.08)
			motor.shoulders([[0.07, 0.1, Tween.TRANS_QUAD, Tween.EASE_OUT], [0.01, 0.3]])
			return motor.shake_head(0.10) + 0.25,
		func() -> float:
			# Turns pointedly away, past centre, and shuts his eyes on it.
			motor.gesture(motor.anchor("lap_" + wave_side), wave_side, 0.7, 0.06)
			motor.set_lids(1.0, 0.4)
			motor.tilt_shoulders(-toward * 0.06, 0.8)
			motor.lean(-0.06, -toward * 0.08, 0.9)
			return motor.turn_head(-toward * 34.0, motor.style({"speed": 0.5, "head_tilt": 8.0}), 10.0) + 1.0,
		func() -> float:
			motor.breathe(1.0, 2.5)
			return motor.return_to_rest(motor.style({"speed": 0.38}), false) + 0.1,
		func() -> float:
			return motor.express("asleep", 1.0, 1.2),
	], Config.FATIGUE_PER_REACTION * 1.3)


## Worn out: one eye creaks open, a glance without lifting his head, an
## enormous yawn behind his hand, and he collapses deeper than before.
func _react_tired(where: Vector3, source: String) -> Dictionary:
	var st: Dictionary = motor.style("tired")
	return _reaction("tired glance (" + source + ")", [
		func() -> float:
			state.activity = "stirring"
			motor.express("tired_peek", st.intensity, 1.0)
			return 1.2,
		func() -> float:
			state.attention = "noise " + source
			state.activity = "glancing"
			motor.look_eyes(where, 0.5)
			return 1.3,
		func() -> float:
			# The yawn: head goes back, shoulders climb, hand comes up.
			state.activity = "yawning"
			motor.express("yawn", 1.0, 0.9)
			motor.turn_head(0.0, motor.style({"speed": 0.35, "head_tilt": 0.0}), 24.0)
			motor.shoulders([[0.06, 1.1], [0.06, 0.7], [-0.05, 1.0]])
			motor.lean(-0.16, 0.0, 1.2)
			motor.sink(0.0, 1.1)
			motor.gesture(motor.anchor("mouth"), "r", 1.0, 0.06, 0.2)
			return 2.3,
		func() -> float:
			state.activity = "sinking back"
			motor.express("tired", st.intensity, 0.8)
			motor.gesture(motor.anchor("lap_r"), "r", 1.3, 0.03)
			motor.lean(0.05, 0.0, 1.4)
			motor.sink(0.07, 1.5)
			return motor.turn_head(-6.0, motor.style({"speed": 0.3, "head_tilt": 0.0}), -32.0) + 0.6,
		func() -> float:
			return motor.return_to_rest(motor.style({"speed": 0.3})) + 0.1,
	], Config.FATIGUE_PER_REACTION * 0.5)


# ---------------------------------------------------------------- frame lifted

## His world lurches. He grabs the edge of the frame with his right hand,
## plants his left on the table, glares out at whoever did it, then lets go.
func _frame_lifted_action() -> Dictionary:
	var book: Node3D = stage.book
	return {
		"name": "frame lifted", "resources": BODY, "priority": 3, "interruptible": true,
		"steps": [
			func() -> float:
				state.attention = "the frame"
				state.activity = "thrown off balance"
				motor.express("alarmed", 1.0, 0.07)
				motor.turn_head(0.0, motor.style({"speed": 2.4, "head_tilt": 0.0}), 4.0)
				motor.shoulders([[0.07, 0.1, Tween.TRANS_QUAD, Tween.EASE_OUT], [0.035, 0.5]])
				motor.sink(-0.01, 0.15)
				motor.breathe(2.4, 0.2, 1.4)
				# The lurch: the torso swings toward his right, as if the floor tipped.
				motor.lean(0.10, -0.20, 0.32)
				motor.tilt_shoulders(0.12, 0.3)
				# Right hand to the edge of the frame.
				motor.brace(stage.point("frame_edge_r"), "r", 0.3, 0.06)
				if motor.is_holding(BOOK_ARM):
					# The book goes down on the table in the same movement as the brace.
					motor.tilt_grip(0.0, BOOK_ARM, 0.25)
					return motor.reach(motor.hand_target_for(book, stage.book_home()), BOOK_ARM, motor.style({"speed": 2.6})) + 0.02
				return motor.brace(stage.point("table_edge"), "l", 0.3, 0.14),
			func() -> float:
				if motor.is_holding(BOOK_ARM):
					motor.release(book, stage, stage.book_home(), BOOK_ARM)
					motor.brace(motor.hand_position(BOOK_ARM), "l", 0.05)
				# Steadies himself, weight still toward the hand on the frame.
				motor.lean(0.07, -0.10, 0.45)
				motor.tilt_shoulders(0.04, 0.45)
				return 0.5,
			func() -> float:
				state.attention = "viewer"
				state.activity = "glaring out"
				motor.lean(0.14, 0.0, 0.5)
				motor.tilt_shoulders(0.0, 0.5)
				motor.express("alarmed", 0.8, 0.2)
				return motor.look_at(stage.point("viewer"), motor.style({"speed": 1.5, "head_tilt": 0.0, "anticipation": 0.0, "head_share": 0.8})) + 0.5,
			func() -> float:
				motor.express("indignant", 1.0, 0.45)
				return 1.5,
			func() -> float:
				motor.shake_head(0.07)
				motor.blink()
				return 0.7,
			func() -> float:
				# Lets go, one hand at a time, and straightens up.
				state.activity = "letting go"
				motor.release_brace("r")
				motor.gesture(motor.anchor("arm_rest_r"), "r", 0.8, 0.05)
				motor.lean(0.0, 0.0, 0.9)
				motor.shoulders([[0.0, 0.8]])
				motor.express("irritated", 0.6, 0.6)
				return 0.9,
			func() -> float:
				motor.release_brace("l")
				motor.gesture(motor.anchor("arm_rest_l"), "l", 0.8, 0.05)
				return 1.0,
			func() -> float:
				state.activity = "settling"
				return motor.return_to_rest(motor.style({"speed": 0.45})) + 0.3,
		],
		"on_end": func(completed: bool) -> Variant:
			motor.release_brace("l")
			motor.release_brace("r")
			if completed:
				state.add_fatigue(Config.FATIGUE_PER_REACTION)
			return _settled(completed),
	}


# ---------------------------------------------------------------- the book

func _book_action() -> Dictionary:
	var st: Dictionary = motor.style("task")
	var book: Node3D = stage.book
	_grasp_failed = false
	var steps: Array = [
		func() -> float:
			state.activity = "waking"
			motor.breathe(1.1, 1.0, 1.0)
			motor.sink(0.0, 1.0)
			motor.shoulders([[0.0, 0.9]])
			motor.tilt_shoulders(0.0, 0.9)
			motor.lean(0.0, 0.0, 1.0)
			motor.gesture(motor.anchor("arm_rest_r"), "r", 0.9, 0.05, 0.3)
			motor.express("neutral", 1.0, 0.7)
			return motor.turn_head(0.0, motor.style({"speed": 0.6, "head_tilt": 0.0})) + 0.2,
		func() -> float:
			state.attention = "book"
			state.activity = "eyeing the book"
			motor.express("curious", 0.6, 0.4)
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
			motor.look_at(reading, motor.style({"speed": 0.6, "head_share": 0.8, "head_tilt": 0.0, "shoulder_follow": 0.0, "anticipation": 0.0}))
			return motor.reach(motor.hand_target_for(book, reading), BOOK_ARM, st) + 0.3,
	]
	steps.append_array(_reading_beats())
	steps.append_array(_put_back_steps())
	return {
		"name": "read the book", "resources": BODY, "priority": 1, "interruptible": true,
		"steps": steps,
		"on_end": _book_ended,
	}


## What reading looks like: a different handful of small performances each
## time, drawn from a pool, so no two sittings play the same.
func _reading_beats() -> Array:
	var pool := ["follow lines", "peer closer", "astonished", "amused", "ponder", "follow lines"]
	var steps: Array = []
	var previous := ""
	for i in 4:
		var beat: String = pool[rng.randi_range(0, pool.size() - 1)]
		if beat == previous:
			beat = "follow lines" if beat != "follow lines" else "peer closer"
		previous = beat
		steps.append_array(_reading_beat(beat, 1.0 if i % 2 == 0 else -1.0))
	return steps


func _reading_beat(beat: String, side: float) -> Array:
	var book: Node3D = stage.book
	match beat:
		"peer closer":
			# Something needs a second look: leans in, squints, one shoulder forward.
			return [
				func() -> float:
					state.activity = "reading: peering closer"
					motor.express("absorbed", 1.0, 0.5)
					motor.lean(0.20, 0.04, 0.8)
					motor.tilt_shoulders(side * 0.07, 0.8)
					motor.tilt_head(side * 9.0, 0.7, 0.15)
					motor.scan_eyes(0.10, -0.10, 1.6)
					return 2.0,
				func() -> float:
					motor.lean(0.04, 0.0, 0.9)
					motor.tilt_shoulders(0.0, 0.9)
					motor.tilt_head(0.0, 0.8)
					return motor.express("content", 1.0, 0.6) + 0.3,
			]
		"astonished":
			# Reads something startling: eyes first, then the head rears back.
			return [
				func() -> float:
					state.activity = "reading: astonished"
					motor.express("astonished", 1.0, 0.12)
					motor.lean(-0.07, 0.0, 0.3, 0.1)
					motor.shoulders([[0.03, 0.2], [0.01, 0.6]], 0.08)
					return 1.0,
				func() -> float:
					# Reads it again to be sure.
					motor.lean(0.14, 0.0, 0.6)
					motor.express("curious", 1.0, 0.4)
					return motor.scan_eyes(0.14, -0.12, 0.9) + 0.2,
				func() -> float:
					motor.lean(0.03, 0.0, 0.8)
					motor.shoulders([[0.0, 0.6]])
					return motor.express("content", 1.0, 0.6) + 0.2,
			]
		"amused":
			# A private chuckle: smile, shoulders bounce, a small nod.
			return [
				func() -> float:
					state.activity = "reading: amused"
					motor.express("amused", 1.0, 0.35)
					motor.tilt_head(side * 7.0, 0.5)
					motor.shoulders([[0.022, 0.11], [0.0, 0.13], [0.02, 0.11], [0.0, 0.13], [0.014, 0.11], [0.0, 0.2]], 0.35)
					return 1.4,
				func() -> float:
					motor.tilt_head(0.0, 0.7)
					motor.express("content", 1.0, 0.7)
					return motor.nod(6.0, 1, 0.6) + 0.2,
			]
		"ponder":
			# Looks up from the page to think: eyes go first, the head follows.
			return [
				func() -> float:
					state.activity = "reading: pondering"
					state.attention = "the distance"
					motor.express("neutral", 1.0, 0.5)
					motor.tilt_head(side * 8.0, 0.9, 0.3)
					return motor.look_at(stage.point("far_left" if side < 0.0 else "far_right"), motor.style({"speed": 0.55, "head_share": 0.6, "head_delay": 0.35, "head_tilt": 0.0, "anticipation": 0.0, "shoulder_follow": 0.1})) + 1.3,
				func() -> float:
					motor.blink()
					motor.nod(4.0, 1, 0.5)
					return 0.7,
				func() -> float:
					state.attention = "book"
					motor.tilt_head(0.0, 0.7)
					motor.express("content", 1.0, 0.6)
					return motor.look_at(book.global_position, motor.style({"speed": 0.7, "head_share": 0.8, "head_tilt": 0.0, "shoulder_follow": 0.0, "anticipation": 0.0})) + 0.3,
			]
		_:
			# Plain reading: eyes down the page, a slight tilt that changes side.
			return [
				func() -> float:
					state.activity = "reading"
					state.attention = "book"
					motor.tilt_head(side * 5.0, 1.2)
					return motor.scan_eyes(0.16, -0.16, 1.25) + 0.1,
				func() -> float:
					motor.blink()
					return motor.scan_eyes(0.16, -0.14, 1.1) + 0.1,
			]


func _put_back_steps() -> Array:
	var st: Dictionary = motor.style("task")
	var book: Node3D = stage.book
	return [
		func() -> float:
			# Nothing to put back if something else already dealt with the book.
			if not motor.is_holding(BOOK_ARM):
				return -1.0
			state.attention = "table"
			state.activity = "putting the book back"
			motor.express("neutral", 1.0, 0.5)
			motor.tilt_head(0.0, 0.5)
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
			return motor.return_to_rest(motor.style({"speed": 0.5})) + 0.3,
	]


## Called when the book routine finishes or is cut short. If he was
## interrupted with the book in his hand, he must still put it back.
func _book_ended(completed: bool) -> Variant:
	_settled(completed)
	if completed:
		state.add_fatigue(Config.FATIGUE_PER_TASK)
		return null
	if motor.is_holding(BOOK_ARM):
		return {
			"name": "put the book back", "resources": BODY, "priority": 1, "interruptible": false,
			"steps": _put_back_steps(), "on_end": _settled,
		}
	if _grasp_failed:
		# Could not get hold of it: a small shrug, then back to rest.
		_grasp_failed = false
		return {
			"name": "give up on the book", "resources": BODY, "priority": 1, "interruptible": true,
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
	return {"name": action_name, "resources": resources, "priority": 0, "interruptible": true, "steps": steps, "on_end": _settled}


## Picks something to do unprompted, weighted by mood and fatigue, never the
## same thing twice running.
func _pick_idle() -> Dictionary:
	var options := {"sleep: head lolls": 2.0, "sleep: shifts in the chair": 1.5, "sleep: snort": 1.0}
	match state.mood:
		"calm":
			options["look around"] = 2.5
			if state.fatigue < 0.45:
				options["read the book"] = 2.5
		"irritated":
			options["suspicious peek"] = 4.0
		"tired":
			options["sleep: head lolls"] = 4.0
			options["sleep: shifts in the chair"] = 3.0
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
		"sleep: shifts in the chair":
			return _idle_shift()
		"sleep: snort":
			return _idle_snort()
		_:
			return _idle_head_lolls()


func _idle_look_around() -> Dictionary:
	var names := ["viewer", "right", "left", "book"]
	var first: String = names[rng.randi_range(0, names.size() - 1)]
	var second: String = names[rng.randi_range(0, names.size() - 1)]
	var st: Dictionary = motor.style({"speed": 0.8})
	return _idle("look around", HEAD, [
		func() -> float:
			state.activity = "waking"
			motor.sink(0.01, 1.0)
			motor.lean(0.0, 0.0, 1.0)
			motor.breathe(1.0, 1.0, 1.0)
			motor.express("neutral", 1.0, 0.8)
			return motor.turn_head(0.0, motor.style({"speed": 0.6, "head_tilt": 0.0})) + 0.2,
		func() -> float:
			state.attention = first
			state.activity = "looking around"
			return motor.look_at(_point(first), st) + rng.randf_range(0.8, 1.6),
		func() -> float:
			motor.blink()
			state.attention = second
			return motor.look_at(_point(second), st) + rng.randf_range(0.6, 1.4),
		func() -> float:
			return motor.return_to_rest(motor.style({"speed": 0.45})) + 0.3,
	])


func _idle_suspicious_peek() -> Dictionary:
	var where: Vector3 = stage.point(_last_noise)
	return _idle("suspicious peek", HEAD, [
		func() -> float:
			state.attention = "noise " + _last_noise
			state.activity = "peeking"
			motor.express("irritated", 0.8, 0.5)
			motor.look_eyes(where, 0.5)
			return 1.6,
		func() -> float:
			return motor.return_to_rest(motor.style({"speed": 0.45})) + 0.3,
	])


## Asleep: the head slides slowly off to the other side, then is hauled back.
func _idle_head_lolls() -> Dictionary:
	return _idle("sleep: head lolls", ["head"], [
		func() -> float:
			state.activity = "asleep: head lolling"
			motor.tilt_head(-16.0, 2.4)
			return motor.turn_head(-14.0, motor.style({"speed": 0.2, "head_tilt": 0.0}), 4.0) + 0.6,
		func() -> float:
			# The jerk of someone catching himself, without waking.
			motor.tilt_head(8.0, 0.25)
			return motor.turn_head(4.0, motor.style({"speed": 2.0, "head_tilt": 0.0}), 12.0) + 0.6,
		func() -> float:
			return motor.return_to_rest(motor.style({"speed": 0.35})) + 0.2,
	])


## Asleep: a slow change of position, weight from one side to the other.
func _idle_shift() -> Dictionary:
	var side := 1.0 if rng.randf() < 0.5 else -1.0
	return _idle("sleep: shifts in the chair", ["torso"], [
		func() -> float:
			state.activity = "asleep: shifting"
			motor.lean(-0.08, side * 0.12, 1.6)
			motor.tilt_shoulders(side * 0.10, 1.6)
			return motor.shoulders([[0.02, 1.0], [-0.045, 1.4]]) + 1.0,
		func() -> float:
			return motor.return_to_rest(motor.style({"speed": 0.3})) + 0.2,
	])


## Asleep: a snore catches, the shoulders hitch, the mouth works, and he subsides.
func _idle_snort() -> Dictionary:
	return _idle("sleep: snort", ["head", "torso"], [
		func() -> float:
			state.activity = "asleep: snorting"
			motor.shoulders([[0.035, 0.12, Tween.TRANS_QUAD, Tween.EASE_OUT], [-0.035, 0.7]])
			motor.express("asleep", 0.3, 0.12)
			return motor.nod(-7.0, 1, 0.5) + 0.2,
		func() -> float:
			return motor.express("asleep", 1.0, 0.9) + 0.4,
	])


func _point(point_name: String) -> Vector3:
	if point_name == "book":
		return stage.book.global_position
	return stage.point(point_name)
