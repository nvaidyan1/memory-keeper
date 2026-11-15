extends Node3D
## The furniture and props the character uses: chair, table, book, and the
## named places the behaviour layer can refer to. The scenery behind them
## lives in backdrop.gd.

const WOOD := Color(0.42, 0.29, 0.19)
const WOOD_DARK := Color(0.30, 0.20, 0.14)
const CUSHION := Color(0.52, 0.24, 0.20)
const BOOK_RED := Color(0.60, 0.18, 0.15)
const PAGE := Color(0.93, 0.89, 0.78)

const TABLE_TOP_Y := 0.70
const BOOK_HALF_HEIGHT := 0.0175

## Two places on the table where the book can rest.
const BOOK_SLOTS := [
	Vector3(0.52, TABLE_TOP_Y + BOOK_HALF_HEIGHT, 0.24),
	Vector3(0.66, TABLE_TOP_Y + BOOK_HALF_HEIGHT, 0.07),
]

## Where disturbances come from: off to either side, and from the viewer.
const NOISE_POINTS := {
	"left": Vector3(-1.3, 1.25, 2.0),
	"right": Vector3(1.4, 1.5, 1.8),
	"viewer": Vector3(0.14, 1.1, 2.9),
}

var book: Node3D
var book_slot := 0
var _markers := {}
var _materials := {}


func _ready() -> void:
	_build()


func book_home() -> Vector3:
	return BOOK_SLOTS[book_slot]


## Puts the book straight back on its slot. Only for reset and slot changes.
func place_book_at_slot(slot: int) -> void:
	book_slot = slot
	if book.get_parent() != self:
		book.reparent(self, true)
	book.position = BOOK_SLOTS[slot]
	book.rotation = Vector3.ZERO


## Slides the book across the table to the other slot (the "someone moved
## my book" test). Not instant, so nothing on screen ever jumps.
func slide_book_to_slot(slot: int) -> void:
	book_slot = slot
	var tween := create_tween()
	tween.tween_property(book, "position", BOOK_SLOTS[slot], 0.6).set_trans(Tween.TRANS_SINE)


## A brief flash where a noise came from, so the cause is visible on screen.
func flash_noise(point_name: String) -> void:
	var marker: MeshInstance3D = _markers.get(point_name)
	if marker == null:
		return
	marker.visible = true
	marker.scale = Vector3.ONE * 0.4
	var tween := create_tween()
	tween.tween_property(marker, "scale", Vector3.ONE * 1.6, 0.35)
	tween.tween_callback(func() -> void: marker.visible = false)


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


func _box(parent: Node3D, size: Vector3, color: Color, pos: Vector3) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = _material(color)
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = pos
	parent.add_child(instance)
	return instance


func _cylinder(parent: Node3D, top: float, bottom: float, height: float, color: Color, pos: Vector3) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = 28
	mesh.material = _material(color)
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = pos
	parent.add_child(instance)
	return instance


func _build() -> void:
	# Chair: seat with a cushion, a low curved-looking back that stops at the
	# shoulders so the head is seen against the view, arm rests and legs.
	_box(self, Vector3(0.60, 0.06, 0.54), WOOD, Vector3(0, 0.43, 0.02))
	_box(self, Vector3(0.52, 0.05, 0.46), CUSHION, Vector3(0, 0.475, 0.04))
	_box(self, Vector3(0.60, 0.50, 0.06), WOOD, Vector3(0, 0.86, -0.25))
	_box(self, Vector3(0.48, 0.38, 0.03), CUSHION, Vector3(0, 0.86, -0.215))
	_box(self, Vector3(0.66, 0.05, 0.09), WOOD_DARK, Vector3(0, 1.125, -0.25))
	for x: float in [-0.31, 0.31]:
		_box(self, Vector3(0.06, 0.045, 0.48), WOOD_DARK, Vector3(x, 0.665, 0.02))
		_box(self, Vector3(0.055, 0.66, 0.055), WOOD, Vector3(x, 0.33, 0.24))
		_box(self, Vector3(0.055, 1.10, 0.055), WOOD, Vector3(x, 0.55, -0.25))

	# Round side table on a pedestal, on the character's left.
	_cylinder(self, 0.28, 0.28, 0.035, WOOD_DARK, Vector3(0.61, TABLE_TOP_Y - 0.0175, 0.17))
	_cylinder(self, 0.045, 0.06, TABLE_TOP_Y - 0.08, WOOD, Vector3(0.61, (TABLE_TOP_Y - 0.08) / 2.0 + 0.04, 0.17))
	_cylinder(self, 0.17, 0.20, 0.04, WOOD_DARK, Vector3(0.61, 0.02, 0.17))

	# Book: origin at its centre.
	book = Node3D.new()
	book.name = "Book"
	add_child(book)
	_box(book, Vector3(0.16, 0.035, 0.22), BOOK_RED, Vector3.ZERO)
	_box(book, Vector3(0.15, 0.025, 0.21), PAGE, Vector3(0.008, 0, 0))
	place_book_at_slot(0)

	# Noise markers, shown only when a noise happens. Placed just inside the
	# frame in the direction the noise comes from.
	var marker_spots := {
		"left": Vector3(-0.50, 1.50, 0.9),
		"right": Vector3(0.62, 1.55, 0.9),
		"viewer": Vector3(0.14, 0.2, 1.2),
	}
	for point_name: String in marker_spots:
		var mesh := SphereMesh.new()
		mesh.radius = 0.035
		mesh.height = 0.07
		mesh.material = _material(Color(1.0, 0.85, 0.3), true)
		var marker := MeshInstance3D.new()
		marker.mesh = mesh
		marker.position = marker_spots[point_name]
		marker.visible = false
		add_child(marker)
		_markers[point_name] = marker
