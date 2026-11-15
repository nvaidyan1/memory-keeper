extends Node3D
## The visible body: primitive meshes on a pivot hierarchy, plus the
## interpolation that moves them. It knows nothing about moods or routines.
##
## Rig interface (what another rig must provide to reuse the motor controller):
##   drive(channel, value, seconds, trans, ease, delay)   tween one dial
##   drive_seq(channel, keys, delay)                      tween one dial through several values
##   drive_arc(channel, to, lift, seconds, delay)         move a hand along a lifted arc
##   get_value(channel) / rest_value(channel) / channel_names()
##   eye_position() / hand_position(side) / shoulder_position(side) / arm_reach()
##   anchor(name)                                         named places relative to the body, in world space
##   attach_prop(prop, side) / detach_prop(prop, new_parent)
##   snap_to_rest()
##
## Facing: the character looks along +Z. His left is +X. Angles are radians.
## head_yaw/eye_yaw: positive turns toward +X. head_pitch/eye_pitch: positive looks up.
## spine_roll, shoulder_roll, head_roll: positive tips toward +X. sink: metres lower in the seat.

const UPPER_ARM := 0.27
const FOREARM := 0.25

const SKIN := Color(0.86, 0.70, 0.58)
const SKIN_SHADE := Color(0.74, 0.58, 0.47)
const ROBE := Color(0.36, 0.40, 0.52)
const ROBE_DARK := Color(0.27, 0.30, 0.42)
const MANTLE := Color(0.24, 0.26, 0.38)
const TRIM := Color(0.72, 0.58, 0.30)
const HAIR := Color(0.90, 0.89, 0.85)
const BROW := Color(0.60, 0.58, 0.56)
const HAT := Color(0.38, 0.27, 0.38)
const LIP := Color(0.60, 0.34, 0.31)
const IRIS := Color(0.33, 0.43, 0.52)
const DARK := Color(0.08, 0.06, 0.06)
const WHITE := Color(0.95, 0.94, 0.90)

## The home pose: fast asleep. Head lolled back and to one side, mouth open,
## sunk into the chair, one arm on the arm rest and the other hanging over it.
const REST := {
	"head_yaw": 0.30, "head_pitch": 0.30, "head_roll": 0.38,
	"eye_yaw": 0.0, "eye_pitch": 0.0,
	"lid_l": 1.0, "lid_r": 1.0, "brow_l": 0.0, "brow_r": 0.0, "brow_angle": 0.0,
	"mouth_curve": 0.0, "mouth_open": 0.45,
	"spine_pitch": -0.13, "spine_roll": 0.07, "spine_yaw": 0.0,
	"shoulder_lift": -0.035, "shoulder_yaw": 0.0, "shoulder_roll": 0.07,
	"sink": 0.045,
	"breath_rate": 0.62, "breath_depth": 2.2,
	"hand_l": Vector3(0.315, 0.725, 0.13), "hand_r": Vector3(-0.42, 0.50, 0.05),
	"grip_tilt_l": 0.0, "grip_tilt_r": 0.0,
}

var channels := {}
var _tweens := {}
var _materials := {}
var _breath_phase := 0.0

var _spine: Node3D
var _torso: MeshInstance3D
var _shoulders: Node3D
var _neck: Node3D
var _arms := {}     # side -> {upper, fore, grip, pole}
var _eyeballs := {} # side -> Node3D, rotates with the gaze
var _lids := {}     # side -> upper eyelid, a half shell that rolls over the eye
var _lower_lids := {}
var _moustache := {}
var _brows := {}    # side -> Node3D
var _brow_base_y := 0.0
var _mouth_l: Node3D
var _mouth_r: Node3D
var _mouth_gap: MeshInstance3D
var _eye_anchor: Node3D


func _ready() -> void:
	_build()
	snap_to_rest()


# ---------------------------------------------------------------- interface

func channel_names() -> Array:
	return REST.keys()


func get_value(channel: String) -> Variant:
	return channels[channel]


func rest_value(channel: String) -> Variant:
	return REST[channel]


func drive(channel: String, value: Variant, seconds := 0.3, trans := Tween.TRANS_SINE,
		ease := Tween.EASE_IN_OUT, delay := 0.0) -> void:
	drive_seq(channel, [[value, seconds, trans, ease]], delay)


## keys: [[value, seconds, trans, ease], ...]; trans and ease are optional.
func drive_seq(channel: String, keys: Array, delay := 0.0) -> void:
	var tween := _fresh_tween(channel)
	var from: Variant = channels[channel]
	var first := true
	for key: Array in keys:
		var trans: int = key[2] if key.size() > 2 else Tween.TRANS_SINE
		var ease: int = key[3] if key.size() > 3 else Tween.EASE_IN_OUT
		var step := tween.tween_method(_set_channel.bind(channel), from, key[0], maxf(key[1], 0.001))
		step.set_trans(trans).set_ease(ease)
		if first and delay > 0.0:
			step.set_delay(delay)
		first = false
		from = key[0]


## Moves a Vector3 dial from where it is to `to`, lifted by `lift` metres mid-way.
func drive_arc(channel: String, to: Vector3, lift: float, seconds: float, delay := 0.0) -> void:
	var tween := _fresh_tween(channel)
	var from: Vector3 = channels[channel]
	var step := tween.tween_method(_set_arc.bind(channel, from, to, lift), 0.0, 1.0, maxf(seconds, 0.001))
	step.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if delay > 0.0:
		step.set_delay(delay)


func eye_position() -> Vector3:
	return _eye_anchor.global_position


## A point 1 m in front of the face, for measuring where the head points.
func gaze_point() -> Vector3:
	return _eye_anchor.global_position + _eye_anchor.global_basis.z


func hand_position(side: String) -> Vector3:
	return _arms[side].grip.global_position


func shoulder_position(side: String) -> Vector3:
	return _arms[side].upper.global_position


## Places defined by this body's proportions, so routines need no coordinates.
func anchor(anchor_name: String) -> Vector3:
	match anchor_name:
		"reading":  # where a held book sits to be read
			return to_global(Vector3(0.05, 0.87, 0.37))
		"arm_rest_l":
			return to_global(Vector3(0.315, 0.725, 0.16))
		"arm_rest_r":
			return to_global(Vector3(-0.315, 0.725, 0.16))
		"mouth":  # where a hand goes to cover a yawn
			return to_global(Vector3(-0.03, 1.13, 0.22))
		"wave_l":  # a hand flung out in dismissal
			return to_global(Vector3(0.50, 1.02, 0.30))
		"wave_r":
			return to_global(Vector3(-0.50, 1.02, 0.30))
		"lap_l":
			return to_global(Vector3(0.10, 0.665, 0.30))
		"lap_r":
			return to_global(Vector3(-0.10, 0.665, 0.30))
		_:
			return global_position


func arm_reach() -> float:
	return UPPER_ARM + FOREARM


## Hands the prop to the hand without moving it: its world transform is kept.
func attach_prop(prop: Node3D, side: String) -> void:
	prop.reparent(_arms[side].grip, true)


func detach_prop(prop: Node3D, new_parent: Node3D) -> void:
	prop.reparent(new_parent, true)


## Immediate return to the home pose. Only for reset; everything else tweens.
func snap_to_rest() -> void:
	for tween: Tween in _tweens.values():
		if tween.is_valid():
			tween.kill()
	_tweens.clear()
	channels = REST.duplicate(true)
	_breath_phase = 0.0
	_apply(0.0)


# ---------------------------------------------------------------- animation

func _fresh_tween(channel: String) -> Tween:
	# A new command on a dial replaces the old one and starts from the current
	# value, so interrupting never snaps.
	if _tweens.has(channel) and _tweens[channel].is_valid():
		_tweens[channel].kill()
	var tween := create_tween()
	_tweens[channel] = tween
	return tween


func _set_channel(value: Variant, channel: String) -> void:
	channels[channel] = value


func _set_arc(u: float, channel: String, from: Vector3, to: Vector3, lift: float) -> void:
	channels[channel] = from.lerp(to, u) + Vector3.UP * (lift * 4.0 * u * (1.0 - u))


func _f(channel: String) -> float:
	return channels[channel]


func _process(delta: float) -> void:
	_apply(delta)


func _apply(delta: float) -> void:
	_breath_phase += delta * _f("breath_rate") * TAU / 4.6
	# The depth of each breath wanders a little, so sleep never looks metronomic.
	var depth := _f("breath_depth") * (1.0 + 0.25 * sin(_breath_phase * 0.23) + 0.12 * sin(_breath_phase * 0.071 + 1.0))
	var breath := (sin(_breath_phase) * 0.5 + 0.5) * depth

	_spine.rotation = Vector3(_f("spine_pitch"), _f("spine_yaw"), -_f("spine_roll"))
	_torso.scale = Vector3(1.0 + 0.025 * breath, 1.0, 0.8 * (1.0 + 0.05 * breath))
	_spine.position.y = -_f("sink")
	_shoulders.position.y = 0.48 + _f("shoulder_lift") + 0.008 * breath
	_shoulders.rotation = Vector3(0.0, _f("shoulder_yaw"), -_f("shoulder_roll"))
	_neck.rotation = Vector3(-_f("head_pitch"), _f("head_yaw"), -_f("head_roll"))

	for side: String in ["l", "r"]:
		var closed := clampf(_f("lid_" + side), 0.0, 1.0)
		# The upper lid is a half shell: rolled back it bares the eye, rolled
		# forward it covers it. The lower lid rises a little as the eye narrows.
		_lids[side].rotation.x = lerpf(deg_to_rad(-58.0), deg_to_rad(90.0), closed)
		_lower_lids[side].rotation.x = PI + 0.62 - 0.40 * closed
		_eyeballs[side].rotation = Vector3(-_f("eye_pitch"), _f("eye_yaw"), 0.0)
		var sign := 1.0 if side == "l" else -1.0
		var brow: Node3D = _brows[side]
		brow.position.y = _brow_base_y + _f("brow_" + side) * 0.02
		brow.rotation.z = sign * _f("brow_angle") * 0.45
		# The moustache droops with a frown and lifts with a smile.
		_moustache[side].rotation.z = sign * (-0.42 + _f("mouth_curve") * 0.3)
		_solve_arm(side)

	var curve := _f("mouth_curve") * 0.55
	_mouth_l.rotation.z = curve
	_mouth_r.rotation.z = -curve
	_mouth_gap.scale.y = lerpf(0.05, 1.0, clampf(_f("mouth_open"), 0.0, 1.0))


## Two-segment arm: places the elbow analytically so the hand lands on its
## target, or as near as the arm allows. An approximation, not a full IK solver:
## no joint limits beyond the reach clamp, and the elbow direction is fixed.
func _solve_arm(side: String) -> void:
	var arm: Dictionary = _arms[side]
	var upper: Node3D = arm.upper
	var fore: Node3D = arm.fore
	var grip: Node3D = arm.grip
	var shoulder := upper.global_position
	var target := to_global(channels["hand_" + side])
	var to_target := target - shoulder
	var dist := clampf(to_target.length(), absf(UPPER_ARM - FOREARM) + 0.01, UPPER_ARM + FOREARM - 0.004)
	var dir := to_target.normalized() if to_target.length() > 0.0001 else Vector3.DOWN
	var cos_a := (UPPER_ARM * UPPER_ARM + dist * dist - FOREARM * FOREARM) / (2.0 * UPPER_ARM * dist)
	var sin_a := sqrt(maxf(0.0, 1.0 - cos_a * cos_a))
	var pole: Vector3 = global_basis * arm.pole
	var perp := pole - dir * pole.dot(dir)
	perp = perp.normalized() if perp.length() > 0.0001 else Vector3.BACK
	var elbow := shoulder + dir * (UPPER_ARM * cos_a) + perp * (UPPER_ARM * sin_a)
	var hand := shoulder + dir * dist
	upper.global_basis = _aim(elbow - shoulder, perp)
	fore.global_basis = _aim(hand - elbow, perp)
	# The grip stays level with the world, apart from its own tilt dial, so a
	# held prop does not swing with the forearm.
	grip.global_basis = global_basis * Basis(Vector3.RIGHT, channels["grip_tilt_" + side])


## A basis whose -Y axis points along `down`.
func _aim(down: Vector3, hint: Vector3) -> Basis:
	var y := -down.normalized()
	var x := hint.cross(y)
	if x.length() < 0.001:
		x = Vector3.RIGHT.cross(y)
	x = x.normalized()
	return Basis(x, y, x.cross(y))


# ---------------------------------------------------------------- geometry

func _material(color: Color, two_sided := false) -> StandardMaterial3D:
	var key := [color, two_sided]
	if not _materials.has(key):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = 1.0
		material.metallic_specular = 0.0    # matte: no highlights
		if two_sided:
			material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_materials[key] = material
	return _materials[key]


func _pivot(parent: Node3D, pos: Vector3, node_name := "") -> Node3D:
	var node := Node3D.new()
	if node_name != "":
		node.name = node_name
	node.position = pos
	parent.add_child(node)
	return node


func _part(parent: Node3D, mesh: PrimitiveMesh, color: Color, pos := Vector3.ZERO,
		rot := Vector3.ZERO, scl := Vector3.ONE, two_sided := false) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	mesh.material = _material(color, two_sided)
	instance.mesh = mesh
	instance.position = pos
	instance.rotation = rot
	instance.scale = scl
	parent.add_child(instance)
	return instance


func _box(size: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh


func _sphere(radius: float) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 28
	mesh.rings = 14
	return mesh


func _half_sphere(radius: float) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius
	mesh.is_hemisphere = true
	mesh.radial_segments = 24
	mesh.rings = 8
	return mesh


func _capsule(radius: float, height: float) -> CapsuleMesh:
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = height
	return mesh


func _cone(top: float, bottom: float, height: float) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = 28
	return mesh


func _build() -> void:
	var hips := _pivot(self, Vector3(0, 0.52, 0), "Hips")

	# Seated robe: one draped mass over the lap, falling from the knees, with
	# shoes showing. Static; it hides the legs entirely.
	_part(hips, _sphere(0.20), ROBE_DARK, Vector3(0, 0.0, 0.17), Vector3.ZERO, Vector3(1.32, 0.50, 1.38))
	_part(hips, _cone(0.20, 0.26, 0.50), ROBE_DARK, Vector3(0, -0.27, 0.37), Vector3(-0.08, 0, 0), Vector3(1.12, 1.0, 0.62))
	_part(hips, _cone(0.265, 0.265, 0.025), TRIM, Vector3(0, -0.505, 0.385), Vector3.ZERO, Vector3(1.12, 1.0, 0.62))
	for x: float in [-0.10, 0.10]:
		_part(hips, _sphere(0.06), DARK.lightened(0.12), Vector3(x, -0.49, 0.53), Vector3.ZERO, Vector3(0.8, 0.5, 1.5))

	_spine = _pivot(hips, Vector3.ZERO, "Spine")
	_torso = _part(_spine, _cone(0.15, 0.23, 0.58), ROBE, Vector3(0, 0.25, 0), Vector3.ZERO, Vector3(1.0, 1.0, 0.8))
	_part(_spine, _cone(0.235, 0.235, 0.05), TRIM, Vector3(0, 0.08, 0.0), Vector3.ZERO, Vector3(1.0, 1.0, 0.82))   # belt

	_shoulders = _pivot(_spine, Vector3(0, 0.48, 0), "Shoulders")
	# A short mantle over the shoulders hides where the arms join the body.
	_part(_shoulders, _sphere(0.30), MANTLE, Vector3(0, -0.03, 0), Vector3.ZERO, Vector3(1.0, 0.40, 0.66))
	_part(_shoulders, _cone(0.066, 0.085, 0.035), TRIM, Vector3(0, 0.085, 0))            # collar

	for side: String in ["l", "r"]:
		var sign := 1.0 if side == "l" else -1.0
		var upper := _pivot(_shoulders, Vector3(sign * 0.22, 0, 0), "UpperArm_" + side)
		_part(upper, _sphere(0.072), ROBE)                                                   # shoulder
		_part(upper, _cone(0.068, 0.056, UPPER_ARM), ROBE, Vector3(0, -UPPER_ARM / 2.0, 0))
		var fore := _pivot(upper, Vector3(0, -UPPER_ARM, 0), "Forearm_" + side)
		_part(fore, _sphere(0.057), ROBE)                                                    # elbow
		# The sleeve flares toward the wrist and the hand comes out of it.
		_part(fore, _cone(0.054, 0.062, FOREARM - 0.03), ROBE, Vector3(0, -(FOREARM - 0.03) / 2.0, 0))
		_part(fore, _cone(0.064, 0.058, 0.03), ROBE_DARK, Vector3(0, -(FOREARM - 0.03), 0))
		_part(fore, _cone(0.03, 0.034, 0.05), SKIN, Vector3(0, -FOREARM + 0.01, 0))          # wrist
		_part(fore, _sphere(0.042), SKIN, Vector3(0, -FOREARM - 0.022, 0.004), Vector3.ZERO, Vector3(0.95, 1.2, 0.6))
		_part(fore, _sphere(0.016), SKIN, Vector3(-sign * 0.034, -FOREARM - 0.012, 0.012))   # thumb
		var grip := _pivot(fore, Vector3(0, -FOREARM, 0), "Grip_" + side)
		# Elbows bend outward, down and back.
		_arms[side] = {"upper": upper, "fore": fore, "grip": grip, "pole": Vector3(sign * 0.55, -0.55, -0.65)}

	_neck = _pivot(_spine, Vector3(0, 0.55, 0), "Neck")
	_part(_neck, _cone(0.05, 0.072, 0.15), SKIN_SHADE, Vector3(0, 0.02, 0))
	var head := _pivot(_neck, Vector3(0, 0.15, 0.01), "Head")
	_part(head, _sphere(0.125), SKIN, Vector3.ZERO, Vector3.ZERO, Vector3(0.95, 1.06, 1.0))            # skull
	_part(head, _sphere(0.096), SKIN, Vector3(0, -0.058, 0.018), Vector3.ZERO, Vector3(0.94, 0.92, 1.0))  # jaw
	_part(head, _sphere(0.022), SKIN, Vector3(0, -0.006, 0.124), Vector3.ZERO, Vector3(0.8, 1.6, 1.1)) # nose bridge
	_part(head, _sphere(0.021), SKIN_SHADE.lerp(SKIN, 0.5), Vector3(0, -0.032, 0.137))                   # nose tip

	# Hair, beard and hat.
	_part(head, _sphere(0.126), HAIR, Vector3(0, -0.02, -0.04), Vector3.ZERO, Vector3(1.0, 1.1, 0.9))
	for x: float in [-0.108, 0.108]:
		_part(head, _capsule(0.04, 0.27), HAIR, Vector3(x, -0.11, -0.015), Vector3(0.1, 0, 0))
	_part(head, _sphere(0.088), HAIR, Vector3(0, -0.135, 0.062), Vector3.ZERO, Vector3(1.08, 1.0, 0.8))
	_part(head, _cone(0.082, 0.012, 0.22), HAIR, Vector3(0, -0.245, 0.10), Vector3(0.34, 0, 0), Vector3(1.0, 1.0, 0.7))
	_part(head, _cone(0.158, 0.162, 0.014), HAT, Vector3(0, 0.108, -0.03), Vector3(-0.1, 0, 0))
	_part(head, _cone(0.118, 0.122, 0.035), TRIM, Vector3(0, 0.125, -0.028), Vector3(-0.1, 0, 0))
	_part(head, _cone(0.045, 0.118, 0.21), HAT, Vector3(0, 0.245, -0.04), Vector3(-0.1, 0, 0))
	_part(head, _cone(0.0, 0.046, 0.13), HAT, Vector3(0.028, 0.395, -0.062), Vector3(-0.25, 0, -0.5))   # bent tip

	_eye_anchor = _pivot(head, Vector3(0, 0.022, 0.11), "Eyes")
	for side: String in ["l", "r"]:
		var sign := 1.0 if side == "l" else -1.0
		var eye := _pivot(head, Vector3(sign * 0.047, 0.022, 0.092), "Eye_" + side)
		var ball := _pivot(eye, Vector3.ZERO)
		_part(ball, _sphere(0.030), WHITE)
		_part(ball, _sphere(0.0135), IRIS, Vector3(0, 0, 0.0262), Vector3.ZERO, Vector3(1, 1, 0.35))
		_part(ball, _sphere(0.0068), DARK, Vector3(0, 0, 0.0292), Vector3.ZERO, Vector3(1, 1, 0.35))
		_eyeballs[side] = ball
		var lid := _pivot(eye, Vector3.ZERO)
		_part(lid, _half_sphere(0.0325), SKIN_SHADE, Vector3.ZERO, Vector3.ZERO, Vector3.ONE, true)
		_lids[side] = lid
		var lower := _pivot(eye, Vector3.ZERO)
		_part(lower, _half_sphere(0.0318), SKIN, Vector3.ZERO, Vector3.ZERO, Vector3.ONE, true)
		_lower_lids[side] = lower
		var brow := _pivot(head, Vector3(sign * 0.05, 0.068, 0.112))
		_part(brow, _capsule(0.011, 0.082), BROW, Vector3.ZERO, Vector3(0, sign * 0.3, PI / 2.0), Vector3(1.0, 1.0, 1.0))
		_brows[side] = brow
	_brow_base_y = 0.068

	# Mouth: two lips hinged at the centre over a dark gap, under a moustache
	# whose halves follow the mouth.
	var mouth := _pivot(head, Vector3(0, -0.082, 0.112))
	_mouth_gap = _part(mouth, _box(Vector3(0.056, 0.036, 0.006)), DARK, Vector3(0, -0.013, -0.003))
	_mouth_l = _pivot(mouth, Vector3.ZERO)
	_part(_mouth_l, _capsule(0.0075, 0.05), LIP, Vector3(0.021, 0, 0), Vector3(0, 0, PI / 2.0))
	_mouth_r = _pivot(mouth, Vector3.ZERO)
	_part(_mouth_r, _capsule(0.0075, 0.05), LIP, Vector3(-0.021, 0, 0), Vector3(0, 0, PI / 2.0))
	for side: String in ["l", "r"]:
		var sign := 1.0 if side == "l" else -1.0
		var half := _pivot(head, Vector3(0, -0.058, 0.126))
		_part(half, _capsule(0.015, 0.085), HAIR, Vector3(sign * 0.04, 0, -0.008), Vector3(0, sign * 0.35, PI / 2.0))
		_moustache[side] = half
