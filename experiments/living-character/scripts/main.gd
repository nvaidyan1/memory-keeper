extends Node3D
## Demo startup: builds the scene, wires the layers together, handles keys
## and draws the debug overlay.
##
## Command-line options (after `--`):
##   --seed=123        deterministic autonomous behaviour
##   --auto            start in autonomous mode
##   --autotest        play a scripted key sequence, record measurements, quit
##   --review          play the six review sequences (86 s), then quit
##   --shots=DIR       with --autotest, save a screenshot twice a second into DIR
##   --camera=DEGREES  camera angle round the character (0 is straight on)
##   --no-overlay      hide the debug text
##   --trace=FILE      write head, hand and book positions every frame as CSV

const CharacterView := preload("res://scripts/character_view.gd")
const Config := preload("res://scripts/config.gd")
const Backdrop := preload("res://scripts/backdrop.gd")
const Stage := preload("res://scripts/stage.gd")
const MotorController := preload("res://scripts/motor_controller.gd")
const ActionScheduler := preload("res://scripts/action_scheduler.gd")
const BehaviourController := preload("res://scripts/behaviour_controller.gd")
const CharacterState := preload("res://scripts/character_state.gd")

var stage: Node3D
var view: Node3D
var motor: Node
var scheduler: Node
var behaviour: Node
var state: RefCounted
var overlay: Label

var _camera_angle: float = Config.CAMERA_ANGLE
var _show_overlay := true
var _trace: FileAccess
var _autotest := false
var _review := false
var _shots_dir := ""
var _clock := 0.0
var _script: Array = []
var _shot_wait := 0.0
var _shot_index := 0
var _last_hand := Vector3.ZERO
var _last_book := Vector3.ZERO
var _max_hand_step := 0.0
var _max_book_step := 0.0
var _measuring := false
var _measure_started := false
var _max_hand_time := 0.0
var _max_book_time := 0.0


func _ready() -> void:
	var seed_value := 0
	var start_auto := false
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			seed_value = int(arg.trim_prefix("--seed="))
		elif arg == "--auto":
			start_auto = true
		elif arg == "--autotest":
			_autotest = true
		elif arg == "--review":
			_autotest = true
			_review = true
		elif arg.begins_with("--shots="):
			_shots_dir = arg.trim_prefix("--shots=")
		elif arg.begins_with("--camera="):
			_camera_angle = float(arg.trim_prefix("--camera="))
		elif arg == "--no-overlay":
			_show_overlay = false
		elif arg.begins_with("--trace="):
			_trace = FileAccess.open(arg.trim_prefix("--trace="), FileAccess.WRITE)
			_trace.store_line("t,action,head_x,head_y,head_z,nose_x,nose_y,nose_z,hand_x,hand_y,hand_z,book_x,book_y,book_z,held")

	_build_world()
	stage = Stage.new()
	stage.name = "Stage"
	add_child(stage)
	view = CharacterView.new()
	view.name = "Character"
	add_child(view)

	state = CharacterState.new()
	motor = MotorController.new()
	motor.name = "Motor"
	add_child(motor)
	motor.setup(view)
	scheduler = ActionScheduler.new()
	scheduler.name = "Scheduler"
	add_child(scheduler)
	behaviour = BehaviourController.new()
	behaviour.name = "Behaviour"
	add_child(behaviour)
	behaviour.setup(motor, scheduler, state, stage, seed_value)

	scheduler.action_started.connect(func(action_name: String) -> void:
		print("%7.2f  start  %s  (mood %s, fatigue %.2f)" % [_clock, action_name, state.mood, state.fatigue])
	)
	scheduler.action_ended.connect(func(action_name: String, completed: bool) -> void:
		print("%7.2f  %s  %s" % [_clock, "end  " if completed else "CUT  ", action_name])
	)

	_build_overlay()
	if start_auto:
		behaviour.set_autonomous(true)
	if _autotest:
		_script = _autotest_script()
		_last_hand = view.hand_position("l")
		_last_book = stage.book.global_position


func _build_world() -> void:
	add_child(Backdrop.new())

	# The camera circles the character at a fixed distance and height.
	var camera := Camera3D.new()
	camera.fov = 34.0
	add_child(camera)
	var aim := Vector3(0.14, 0.93, 0.0)
	var angle := deg_to_rad(_camera_angle)
	camera.position = aim + Vector3(sin(angle) * 2.9, 0.07, cos(angle) * 2.9)
	camera.look_at(aim)
	camera.current = true

	# Soft key from the front, as if from the open side of the loggia, with
	# gentle shadows; a cool fill from the other side; warm ambient.
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-32, 28, 0)
	key.light_energy = 1.05
	key.light_color = Color(1.0, 0.94, 0.84)
	key.shadow_enabled = true
	key.shadow_opacity = 0.45
	key.shadow_blur = 2.5
	add_child(key)

	var fill := OmniLight3D.new()
	fill.position = Vector3(-1.1, 1.5, 1.8)
	fill.light_energy = 0.35
	fill.light_color = Color(0.78, 0.84, 1.0)
	fill.omni_range = 5.0
	add_child(fill)

	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.36, 0.55, 0.78)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.86, 0.80, 0.72)
	environment.ambient_light_energy = 0.42
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)


func _build_overlay() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	overlay = Label.new()
	overlay.position = Vector2(10, 8)
	overlay.add_theme_font_size_override("font_size", 13)
	overlay.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	overlay.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	layer.add_child(overlay)
	layer.visible = _show_overlay


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		press(event.keycode)


func press(keycode: int) -> void:
	match keycode:
		KEY_1:
			behaviour.disturbance("left", "calm")
		KEY_2:
			behaviour.disturbance("left", "irritated")
		KEY_3:
			behaviour.disturbance("left", "tired")
		KEY_4:
			behaviour.read_book()
		KEY_5:
			# Move the book to the other place on the table, if nobody has it.
			if not motor.is_holding("l") and not scheduler.owns("prop"):
				stage.slide_book_to_slot(1 - stage.book_slot)
		KEY_SPACE:
			behaviour.set_autonomous(not behaviour.autonomous)
		KEY_R:
			reset()
		KEY_ESCAPE:
			get_tree().quit()


## Back to a coherent home state: no actions, body at rest, book on the table.
func reset() -> void:
	scheduler.reset()
	motor.reset()
	stage.place_book_at_slot(stage.book_slot)
	state.reset()
	behaviour.set_autonomous(false)
	behaviour.reset()
	print("%7.2f  RESET" % _clock)


func _process(delta: float) -> void:
	_clock += delta
	var running: Array = scheduler.running_names()
	var queued: Array = scheduler.queued_names()
	overlay.text = "\n".join([
		"action     %s" % (", ".join(running) if not running.is_empty() else "none (dozing)"),
		"queued     %s" % (", ".join(queued) if not queued.is_empty() else "-"),
		"doing      %s" % state.activity,
		"mood       %s   fatigue %.2f   recent noises %d" % [state.mood, state.fatigue, state.stimulus_times.size()],
		"attention  %s" % state.attention,
		"last pick  %s" % behaviour.last_choice,
		"autonomous %s%s" % ["ON" if behaviour.autonomous else "off", ("   seed %d" % behaviour.seed_value) if behaviour.seed_value != 0 else ""],
		"book       slot %d%s" % [stage.book_slot, "  (in hand)" if motor.is_holding("l") else ""],
		"",
		"1 curious  2 irritated  3 tired  4 book  5 move book  Space auto  R reset",
	])
	if _trace != null:
		var eyes: Vector3 = view.eye_position()
		var nose: Vector3 = view.gaze_point()
		var hand_now: Vector3 = view.hand_position("l")
		var book_now: Vector3 = stage.book.global_position
		_trace.store_line("%.4f,%s,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%d" % [
			_clock, "+".join(running).replace(",", ";"), eyes.x, eyes.y, eyes.z, nose.x, nose.y, nose.z,
			hand_now.x, hand_now.y, hand_now.z, book_now.x, book_now.y, book_now.z, 1 if motor.is_holding("l") else 0])
	if _autotest:
		_run_autotest(delta)


# ---------------------------------------------------------------- self-test

## [seconds, what]: a key to press, or a note to print.
func _autotest_script() -> Array:
	if _review:
		# The six sequences for motion review, back to back.
		return [
			[1.0, KEY_1], [8.0, KEY_2], [19.0, KEY_3],
			[31.5, KEY_4],                      # book, near position
			[48.0, KEY_5], [49.0, KEY_4],       # book, far position
			[65.5, KEY_4], [74.0, KEY_1],       # noise while reading
			[86.0, "quit"],
		]
	return [
		[1.0, KEY_1], [8.5, KEY_2], [18.5, KEY_3],
		[29.0, KEY_4],                       # book from slot 0
		[52.0, KEY_5], [53.0, KEY_4],        # book from slot 1
		[78.0, KEY_4], [86.5, KEY_1],        # noise while holding the book
		[112.0, KEY_4], [116.0, "measure_off"], [116.1, KEY_R],   # reset mid-reach
		[117.5, "report"], [118.0, KEY_SPACE], [150.0, "quit"],
	]


func _run_autotest(delta: float) -> void:
	if not _measure_started and _clock > 0.5:
		_measure_started = true
		_measuring = true
	# Largest distance the hand and the book travel in one frame. A teleport
	# shows up as a step far larger than any tweened movement.
	var hand: Vector3 = view.hand_position("l")
	var book: Vector3 = stage.book.global_position
	if _measuring:
		if hand.distance_to(_last_hand) > _max_hand_step:
			_max_hand_step = hand.distance_to(_last_hand)
			_max_hand_time = _clock
		if book.distance_to(_last_book) > _max_book_step:
			_max_book_step = book.distance_to(_last_book)
			_max_book_time = _clock
	_last_hand = hand
	_last_book = book

	while not _script.is_empty() and _clock >= _script[0][0]:
		var entry: Array = _script.pop_front()
		var what: Variant = entry[1]
		if what is int:
			print("%7.2f  key    %s" % [_clock, OS.get_keycode_string(what)])
			press(what)
		elif what == "measure_off":
			_measuring = false
		elif what == "report":
			print("%7.2f  REPORT max hand step %.4f m/frame (at %.2f s), max book step %.4f m/frame (at %.2f s), fps %d" % [
				_clock, _max_hand_step, _max_hand_time, _max_book_step, _max_book_time, Engine.get_frames_per_second()])
			print("%7.2f  REPORT after reset: book at %s (slot %s), holding %s, hand at %s, running %s" % [
				_clock, stage.book.global_position, stage.book_home(), motor.is_holding("l"),
				view.hand_position("l"), scheduler.running_names()])
			print("%7.2f  REPORT static memory %.1f MB" % [_clock, OS.get_static_memory_usage() / 1048576.0])
		elif what == "quit":
			get_tree().quit()

	if _shots_dir != "":
		_shot_wait -= delta
		if _shot_wait <= 0.0:
			_shot_wait = 0.5
			_save_shot()


func _save_shot() -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png("%s/%04d_%06.2f.png" % [_shots_dir, _shot_index, _clock])
	_shot_index += 1
