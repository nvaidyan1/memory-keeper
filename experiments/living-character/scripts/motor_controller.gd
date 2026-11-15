extends Node
## Body control. Turns commands such as "look at that point" into dial
## movements on a rig. It decides HOW a movement is performed (using a style),
## never WHICH movement to perform.
##
## Every command starts its tweens and returns the seconds it needs, so a
## caller can sequence commands without the motor owning any schedule.

const Config := preload("res://scripts/config.gd")

const FACE_CHANNELS := ["lid_l", "lid_r", "brow_l", "brow_r", "brow_angle", "mouth_curve", "mouth_open"]

var rig: Node3D
var held := {}            # side -> prop being held
var _grip_offset := {}    # prop -> hand position minus prop position at the moment of grasp
var _prop_tweens: Array[Tween] = []


func setup(character_rig: Node3D) -> void:
	rig = character_rig


func style(mood_or_overrides: Variant = "calm") -> Dictionary:
	if mood_or_overrides is String:
		return Config.STYLES[mood_or_overrides]
	var merged: Dictionary = Config.STYLES["calm"].duplicate()
	merged.merge(mood_or_overrides, true)
	return merged


# ---------------------------------------------------------------- gaze and head

## Turns eyes, then head, then shoulders toward a point in the world.
func look_at(target: Vector3, st: Dictionary = Config.STYLES["calm"]) -> float:
	var offset: Vector3 = target - rig.eye_position()
	var yaw := atan2(offset.x, offset.z)
	var pitch := atan2(offset.y, Vector2(offset.x, offset.z).length())
	return _aim_gaze(yaw, pitch, st)


## Turns the head to an angle (degrees, positive toward his left), eyes level.
func turn_head(angle_degrees: float, st: Dictionary = Config.STYLES["calm"], pitch_degrees := 0.0) -> float:
	var forced := st.duplicate()
	forced["head_share"] = 1.0
	return _aim_gaze(deg_to_rad(angle_degrees), deg_to_rad(pitch_degrees), forced)


func _aim_gaze(yaw: float, pitch: float, st: Dictionary) -> float:
	var speed: float = st.speed
	var turn: float = st.turn_time / speed
	var saccade := 0.09 / speed
	var head_delay: float = st.head_delay / speed
	var eye_delay: float = st.eye_delay / speed

	var head_yaw := clampf(yaw * st.head_share, -Config.MAX_HEAD_YAW, Config.MAX_HEAD_YAW)
	var head_pitch := clampf(pitch * st.head_share, -Config.MAX_HEAD_PITCH, Config.MAX_HEAD_PITCH)
	var eye_yaw := clampf(yaw - head_yaw, -Config.MAX_EYE_ANGLE, Config.MAX_EYE_ANGLE)
	var eye_pitch := clampf(pitch - head_pitch, -Config.MAX_EYE_ANGLE, Config.MAX_EYE_ANGLE)

	# Eyes lead: they dart as far toward the target as they can, then ease
	# back to centre as the head arrives.
	var now_yaw: float = rig.get_value("head_yaw")
	var now_pitch: float = rig.get_value("head_pitch")
	var dart_yaw := clampf(yaw - now_yaw, -Config.MAX_EYE_ANGLE, Config.MAX_EYE_ANGLE)
	var dart_pitch := clampf(pitch - now_pitch, -Config.MAX_EYE_ANGLE, Config.MAX_EYE_ANGLE)
	rig.drive_seq("eye_yaw", [[dart_yaw, saccade, Tween.TRANS_QUAD, Tween.EASE_OUT],
			[dart_yaw, head_delay], [eye_yaw, turn]], eye_delay)
	rig.drive_seq("eye_pitch", [[dart_pitch, saccade, Tween.TRANS_QUAD, Tween.EASE_OUT],
			[dart_pitch, head_delay], [eye_pitch, turn]], eye_delay)

	var start := eye_delay + saccade + head_delay
	var trans: int = st.trans
	var anticipation: float = st.anticipation
	if anticipation > 0.0 and absf(head_yaw - now_yaw) > 0.2:
		# A small move the wrong way first makes the turn read.
		var back := now_yaw - signf(head_yaw - now_yaw) * anticipation
		rig.drive_seq("head_yaw", [[back, 0.11 / speed, Tween.TRANS_SINE, Tween.EASE_OUT],
				[head_yaw, turn, trans, Tween.EASE_IN_OUT]], start)
		start += 0.11 / speed
	else:
		rig.drive("head_yaw", head_yaw, turn, trans, Tween.EASE_OUT if trans == Tween.TRANS_BACK else Tween.EASE_IN_OUT, start)
	rig.drive("head_pitch", head_pitch, turn, Tween.TRANS_SINE, Tween.EASE_IN_OUT, start)
	rig.drive("head_roll", deg_to_rad(st.head_tilt) * signf(head_yaw), turn * 1.3, Tween.TRANS_SINE, Tween.EASE_IN_OUT, start)

	var lag: float = st.shoulder_lag / speed
	rig.drive("shoulder_yaw", head_yaw * st.shoulder_follow, turn * 1.4, Tween.TRANS_SINE, Tween.EASE_IN_OUT, start + lag)
	rig.drive("spine_yaw", head_yaw * st.shoulder_follow * 0.45, turn * 1.6, Tween.TRANS_SINE, Tween.EASE_IN_OUT, start + lag)
	return start + turn + lag * 0.5


## Rolls the eyes up and around toward one side (sign: +1 his left, -1 his right).
func eye_roll(toward: float, seconds := 0.7) -> float:
	var up := Config.MAX_EYE_ANGLE
	rig.drive_seq("eye_pitch", [[up, seconds * 0.35, Tween.TRANS_SINE, Tween.EASE_OUT],
			[up * 0.8, seconds * 0.35], [0.0, seconds * 0.3]])
	rig.drive_seq("eye_yaw", [[-toward * 0.15, seconds * 0.3], [toward * Config.MAX_EYE_ANGLE, seconds * 0.7]])
	return seconds


## Closes both eyes to `amount` (0 open, 1 shut) without changing the rest of the face.
func set_lids(amount: float, seconds := 0.3) -> float:
	rig.drive("lid_l", amount, seconds)
	rig.drive("lid_r", amount, seconds)
	return seconds


## A short shake of the head around wherever it is pointing.
func shake_head(amplitude := 0.08) -> float:
	var yaw: float = rig.get_value("head_yaw")
	rig.drive_seq("head_yaw", [[yaw - amplitude, 0.09], [yaw + amplitude * 0.8, 0.13], [yaw, 0.11]])
	return 0.33


func blink() -> float:
	for side: String in ["l", "r"]:
		var channel := "lid_" + side
		var open: float = rig.get_value(channel)
		if open < 0.9:
			rig.drive_seq(channel, [[1.0, 0.07, Tween.TRANS_QUAD, Tween.EASE_OUT], [open, 0.12]])
	return 0.2


# ---------------------------------------------------------------- face

func express(expression: String, intensity := 1.0, seconds := 0.3, delay := 0.0) -> float:
	var target: Dictionary = Config.EXPRESSIONS[expression]
	var neutral: Dictionary = Config.EXPRESSIONS["neutral"]
	for channel: String in FACE_CHANNELS:
		var value := lerpf(neutral[channel], target[channel], intensity)
		rig.drive(channel, value, seconds, Tween.TRANS_SINE, Tween.EASE_IN_OUT, delay)
	return seconds + delay


# ---------------------------------------------------------------- torso

## Leans the torso. forward and side are radians; side is positive toward his left.
func lean(forward: float, side := 0.0, seconds := 0.5, delay := 0.0) -> float:
	rig.drive("spine_pitch", clampf(forward, -Config.MAX_LEAN, Config.MAX_LEAN), seconds, Tween.TRANS_SINE, Tween.EASE_IN_OUT, delay)
	rig.drive("spine_roll", clampf(side, -Config.MAX_LEAN, Config.MAX_LEAN), seconds, Tween.TRANS_SINE, Tween.EASE_IN_OUT, delay)
	return seconds + delay


## Moves the shoulders through a list of [height in metres, seconds] keys.
func shoulders(keys: Array, delay := 0.0) -> float:
	var total := delay
	for key: Array in keys:
		total += key[1]
	rig.drive_seq("shoulder_lift", keys, delay)
	return total


func breathe(rate: float, seconds := 1.0) -> void:
	rig.drive("breath_rate", rate, seconds)


# ---------------------------------------------------------------- arms and props

## Moves a hand to a point in the world along a lifted arc, leaning the torso
## if the point is beyond comfortable reach. Starts from wherever the hand is.
func reach(target: Vector3, side := "l", st: Dictionary = Config.STYLES["task"]) -> float:
	var seconds: float = Config.REACH_TIME / st.speed
	var needed := lean_needed(target, side)
	lean(needed.y, needed.x, seconds * 0.9)
	var travel: float = rig.hand_position(side).distance_to(target)
	var lift := minf(Config.REACH_ARC, travel * 0.25)
	rig.drive_arc("hand_" + side, rig.to_local(target), lift, seconds, seconds * 0.12)
	return seconds * 1.12


## How far the torso must lean (x: sideways, y: forward) to bring a point
## within comfortable reach. Bounded; a point too far away stays out of reach.
func lean_needed(target: Vector3, side: String) -> Vector2:
	# Measured from where the shoulder sits when upright, so the answer does
	# not depend on how far he is already leaning.
	var upright: Vector3 = rig.shoulder_position(side)
	upright.x = rig.global_position.x + (0.22 if side == "l" else -0.22)
	upright.z = rig.global_position.z
	var offset: Vector3 = target - upright
	var excess: float = offset.length() - rig.arm_reach() * Config.REACH_COMFORT
	if excess <= 0.0:
		return Vector2.ZERO
	var amount := minf(excess * Config.LEAN_PER_METRE, Config.MAX_LEAN)
	var flat := Vector2(offset.x, offset.z).normalized()
	return Vector2(flat.x, flat.y * 0.8) * amount


func hand_position(side := "l") -> Vector3:
	return rig.hand_position(side)


## A named place defined by the body, such as where a book is held to read.
func anchor(anchor_name: String) -> Vector3:
	return rig.anchor(anchor_name)


func can_grasp(prop: Node3D, side := "l") -> bool:
	return rig.hand_position(side).distance_to(grip_point(prop)) <= Config.GRASP_TOLERANCE


## Where the hand should be to take hold of a prop.
func grip_point(prop: Node3D) -> Vector3:
	return prop.global_position + Vector3(0, 0.04, 0)


## Takes hold of a prop if the hand is on it. The prop keeps its place in the
## world at the moment of hand-over, so nothing jumps.
func grasp(prop: Node3D, side := "l") -> bool:
	if held.has(side) or not can_grasp(prop, side):
		return false
	_grip_offset[prop] = rig.hand_position(side) - prop.global_position
	rig.attach_prop(prop, side)
	held[side] = prop
	return true


func is_holding(side := "l") -> bool:
	return held.has(side)


## Where the hand must go for a held prop to sit at `prop_position`.
func hand_target_for(prop: Node3D, prop_position: Vector3) -> Vector3:
	return prop_position + _grip_offset.get(prop, Vector3(0, 0.04, 0))


## Lets go of a prop, handing it to `new_parent` where it is, then settles it
## the last few millimetres onto `rest_position`.
func release(prop: Node3D, new_parent: Node3D, rest_position: Vector3, side := "l") -> float:
	if held.get(side) != prop:
		return 0.0
	rig.detach_prop(prop, new_parent)
	held.erase(side)
	_grip_offset.erase(prop)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(prop, "global_position", rest_position, 0.14)
	tween.tween_property(prop, "rotation", Vector3.ZERO, 0.14)
	_prop_tweens.append(tween)
	return 0.2


## Tilts what the hand holds toward the face (radians).
func tilt_grip(angle: float, side := "l", seconds := 0.6, delay := 0.0) -> float:
	rig.drive("grip_tilt_" + side, angle, seconds, Tween.TRANS_SINE, Tween.EASE_IN_OUT, delay)
	return seconds + delay


# ---------------------------------------------------------------- home

## Eases every dial back to the home pose. A hand that is holding something
## keeps holding it where it is.
func return_to_rest(st: Dictionary = Config.STYLES["calm"], include_face := true) -> float:
	var seconds: float = 1.1 / st.speed
	for channel: String in rig.channel_names():
		if channel.begins_with("hand_") or channel.begins_with("grip_tilt_"):
			var side := channel.right(1)
			if held.has(side):
				continue
			if channel.begins_with("hand_"):
				rig.drive_arc(channel, rig.rest_value(channel), Config.REACH_ARC * 0.5, seconds)
				continue
		if not include_face and channel in FACE_CHANNELS:
			continue
		rig.drive(channel, rig.rest_value(channel), seconds)
	return seconds


## Immediate, for reset only. Returns any held props so the caller can put them back.
func reset() -> Array:
	for tween: Tween in _prop_tweens:
		if tween.is_valid():
			tween.kill()
	_prop_tweens.clear()
	var dropped := held.values()
	held.clear()
	_grip_offset.clear()
	rig.snap_to_rest()
	return dropped
