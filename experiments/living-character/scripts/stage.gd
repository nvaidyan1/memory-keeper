extends Node3D
## The set: chair, table, book and the places things can be. Static geometry
## plus named points the behaviour layer can refer to.

const WOOD := Color(0.45, 0.30, 0.16)
const WOOD_DARK := Color(0.30, 0.19, 0.10)
const BOOK_RED := Color(0.62, 0.14, 0.12)
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
		material.roughness = 0.85
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


func _build() -> void:
	# Floor and back wall.
	_box(self, Vector3(4, 0.04, 4), Color(0.20, 0.15, 0.12), Vector3(0, -0.02, 0))
	_box(self, Vector3(4, 3, 0.05), Color(0.16, 0.12, 0.11), Vector3(0, 1.5, -0.6))

	# Chair: seat, tall back, arm rests, legs.
	_box(self, Vector3(0.58, 0.07, 0.52), WOOD, Vector3(0, 0.44, 0.02))
	_box(self, Vector3(0.62, 1.15, 0.07), WOOD, Vector3(0, 0.98, -0.25))
	_box(self, Vector3(0.50, 0.95, 0.03), WOOD_DARK, Vector3(0, 1.0, -0.21))
	for x: float in [-0.31, 0.31]:
		_box(self, Vector3(0.06, 0.05, 0.46), WOOD, Vector3(x, 0.66, 0.03))
		_box(self, Vector3(0.06, 0.66, 0.06), WOOD, Vector3(x, 0.33, 0.24))
		_box(self, Vector3(0.06, 0.44, 0.06), WOOD, Vector3(x, 0.22, -0.22))

	# Side table on the character's left.
	_box(self, Vector3(0.38, 0.04, 0.46), WOOD_DARK, Vector3(0.61, TABLE_TOP_Y - 0.02, 0.17))
	_box(self, Vector3(0.07, TABLE_TOP_Y - 0.04, 0.07), WOOD_DARK, Vector3(0.61, (TABLE_TOP_Y - 0.04) / 2.0, 0.17))

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
		"left": Vector3(-0.42, 1.55, 0.5),
		"right": Vector3(0.72, 1.6, 0.5),
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
