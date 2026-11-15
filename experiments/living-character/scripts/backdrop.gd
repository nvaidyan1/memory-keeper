extends Node3D
## The world behind the character: sky, distant landscape and the loggia he
## sits in. Purely scenery. Nothing here is touched by the character code.
##
## Everything beyond the wall is unshaded flat colour, like a painted
## backcloth. Only the sky moves, and only by sliding its cloud texture.

const Config := preload("res://scripts/config.gd")

const STONE := Color(0.63, 0.57, 0.48)
const STONE_SHADE := Color(0.50, 0.45, 0.38)
const STONE_LIGHT := Color(0.68, 0.62, 0.52)
const FLOOR := Color(0.47, 0.41, 0.35)

const WALL_Z := -1.0
const ARCH_HALF_WIDTH := 0.86
const ARCH_SPRING := 1.32        # height where the curve of the arch begins

const SKY_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform sampler2D clouds : repeat_enable, filter_linear;
uniform float drift = 0.0;
uniform vec3 zenith : source_color = vec3(0.36, 0.55, 0.78);
uniform vec3 horizon : source_color = vec3(0.86, 0.84, 0.74);
void fragment() {
	vec3 sky = mix(zenith, horizon, smoothstep(0.15, 0.72, UV.y));
	vec2 uv = UV * vec2(2.0, 2.6);
	// Two layers sliding at different speeds, so the shapes slowly change
	// and no pattern is seen to repeat.
	float n = texture(clouds, uv + vec2(TIME * drift, 0.0)).r * 0.65
			+ texture(clouds, uv * 2.1 + vec2(TIME * drift * 1.7, 0.31)).r * 0.35;
	float cloud = smoothstep(0.50, 0.70, n) * smoothstep(0.80, 0.35, UV.y);
	ALBEDO = mix(sky, vec3(0.96, 0.93, 0.86), cloud * 0.9);
}
"""

## A wall with an arched opening cut out of it, and a paler band round the arch.
const WALL_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform vec2 size;
uniform float half_width;
uniform float spring;
uniform vec3 stone : source_color;
uniform vec3 trim : source_color;
void fragment() {
	vec2 p = vec2((UV.x - 0.5) * size.x, (1.0 - UV.y) * size.y);
	float d = p.y < spring ? abs(p.x) - half_width : length(vec2(p.x, p.y - spring)) - half_width;
	if (d < 0.0) { discard; }
	float band = 1.0 - smoothstep(0.13, 0.14, d);
	float courses = 0.96 + 0.04 * step(0.5, fract(p.y / 0.42));
	ALBEDO = mix(stone * courses, trim, band);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
"""

var _materials := {}


func _ready() -> void:
	_build_sky()
	_build_landscape()
	_build_loggia()


func _flat(color: Color) -> StandardMaterial3D:
	return _material(color, true)


func _material(color: Color, unshaded := false) -> StandardMaterial3D:
	var key := [color, unshaded]
	if not _materials.has(key):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = 1.0
		material.metallic_specular = 0.0
		if unshaded:
			material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_materials[key] = material
	return _materials[key]


func _add(mesh: PrimitiveMesh, material: Material, pos: Vector3, scl := Vector3.ONE, rot := Vector3.ZERO) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	mesh.material = material
	instance.mesh = mesh
	instance.position = pos
	instance.scale = scl
	instance.rotation = rot
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
	return instance


func _box(size: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh


func _cylinder(top: float, bottom: float, height: float) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = 24
	return mesh


func _ball() -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	return mesh


func _build_sky() -> void:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.012
	noise.fractal_octaves = 4
	noise.seed = 11
	var texture := NoiseTexture2D.new()
	texture.width = 256
	texture.height = 256
	texture.seamless = true      # tiles without an edge, so the drift never shows a seam
	texture.noise = noise
	var shader := Shader.new()
	shader.code = SKY_SHADER
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("clouds", texture)
	material.set_shader_parameter("drift", Config.CLOUD_SPEED if Config.CLOUD_DRIFT else 0.0)
	var quad := QuadMesh.new()
	quad.size = Vector2(60, 30)
	_add(quad, material, Vector3(0, 9.0, -24.0))


func _build_landscape() -> void:
	# Far mountains, hazy and blue; nearer hills greener and darker.
	var far := _flat(Color(0.60, 0.68, 0.72))
	_add(_ball(), far, Vector3(-7.0, 0.0, -19.0), Vector3(8.0, 5.2, 1.0))
	_add(_ball(), far, Vector3(4.5, 0.0, -20.0), Vector3(9.0, 4.2, 1.0))
	_add(_ball(), far, Vector3(14.0, 0.0, -19.5), Vector3(7.0, 5.6, 1.0))
	var mid := _flat(Color(0.52, 0.62, 0.50))
	_add(_ball(), mid, Vector3(-3.5, -0.4, -13.0), Vector3(6.0, 2.9, 1.0))
	_add(_ball(), mid, Vector3(6.0, -0.4, -13.5), Vector3(7.0, 2.5, 1.0))
	var near := _flat(Color(0.42, 0.52, 0.34))
	_add(_ball(), near, Vector3(1.0, -0.6, -8.5), Vector3(7.5, 1.9, 1.0))
	_add(_ball(), near, Vector3(-6.5, -0.6, -8.0), Vector3(4.0, 2.2, 1.0))

	# A small temple on the far hill.
	var marble := _flat(Color(0.90, 0.86, 0.76))
	_add(_box(Vector3(1.5, 0.75, 0.6)), marble, Vector3(-1.6, 2.5, -13.2))
	var pediment := PrismMesh.new()
	pediment.size = Vector3(1.7, 0.36, 0.6)
	_add(pediment, _flat(Color(0.80, 0.70, 0.58)), Vector3(-1.6, 3.05, -13.2))

	# Cypresses and round pines between the hills and the wall.
	var cypress := _flat(Color(0.20, 0.30, 0.22))
	for spot: Array in [[-2.3, 2.5, -7.0], [-1.85, 1.9, -7.3], [1.75, 2.3, -7.4], [2.2, 1.7, -7.8]]:
		_add(_cylinder(0.0, 0.33, spot[1]), cypress, Vector3(spot[0], 0.9 + spot[1] / 2.0, spot[2]))
	var pine := _flat(Color(0.30, 0.42, 0.26))
	var trunk := _flat(Color(0.36, 0.27, 0.20))
	for spot: Array in [[-3.3, -6.4], [4.3, -6.6]]:
		_add(_cylinder(0.05, 0.07, 1.3), trunk, Vector3(spot[0], 1.55, spot[1]))
		_add(_ball(), pine, Vector3(spot[0], 2.3, spot[1]), Vector3(0.75, 0.36, 0.3))


func _build_loggia() -> void:
	var stone := _material(STONE)
	var shade := _material(STONE_SHADE)
	var light := _material(STONE_LIGHT)

	# Floor, with a paler border strip along the back.
	_add(_box(Vector3(7, 0.04, 6)), _material(FLOOR), Vector3(0, -0.02, 1.0))
	_add(_box(Vector3(7, 0.045, 0.5)), light, Vector3(0, -0.02, WALL_Z + 0.35))

	# Back wall with the arched opening.
	var size := Vector2(7.0, 4.2)
	var shader := Shader.new()
	shader.code = WALL_SHADER
	var wall_material := ShaderMaterial.new()
	wall_material.shader = shader
	wall_material.set_shader_parameter("size", size)
	wall_material.set_shader_parameter("half_width", ARCH_HALF_WIDTH)
	wall_material.set_shader_parameter("spring", ARCH_SPRING)
	wall_material.set_shader_parameter("stone", STONE_SHADE)
	wall_material.set_shader_parameter("trim", STONE)
	var quad := QuadMesh.new()
	quad.size = size
	_add(quad, wall_material, Vector3(0, size.y / 2.0, WALL_Z))

	# Columns standing just in front of the wall at each side of the arch.
	for x: float in [-(ARCH_HALF_WIDTH + 0.14), ARCH_HALF_WIDTH + 0.14]:
		var z := WALL_Z + 0.2
		_add(_box(Vector3(0.36, 0.10, 0.36)), light, Vector3(x, 0.05, z))
		_add(_cylinder(0.15, 0.15, 0.07), light, Vector3(x, 0.135, z))
		_add(_cylinder(0.105, 0.125, ARCH_SPRING - 0.30), stone, Vector3(x, 0.17 + (ARCH_SPRING - 0.30) / 2.0, z))
		_add(_cylinder(0.16, 0.11, 0.08), light, Vector3(x, ARCH_SPRING - 0.09, z))
		_add(_box(Vector3(0.36, 0.07, 0.36)), light, Vector3(x, ARCH_SPRING - 0.015, z))

	# Parapet across the opening, with a capping stone.
	_add(_box(Vector3(ARCH_HALF_WIDTH * 2.0, 0.62, 0.14)), shade, Vector3(0, 0.31, WALL_Z - 0.02))
	_add(_box(Vector3(ARCH_HALF_WIDTH * 2.0 + 0.06, 0.06, 0.22)), light, Vector3(0, 0.65, WALL_Z - 0.02))

	# Ground beyond the wall, so nothing is ever empty below the hills.
	_add(_box(Vector3(60, 0.1, 30)), _flat(Color(0.42, 0.52, 0.34)), Vector3(0, 0.6, -16.0))
