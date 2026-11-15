extends Node3D
## Demo startup: builds the scene, wires the layers together, handles keys
## and draws the debug overlay.
##
## Command-line options (after `--`):
##   --seed=123        deterministic autonomous behaviour
##   --auto            start in autonomous mode
##   --autotest        play a scripted key sequence, record measurements, quit
##   --shots=DIR       with --autotest, save a screenshot twice a second into DIR

const CharacterView := preload("res://scripts/character_view.gd")
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

var _autotest := false
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
		elif arg.begins_with("--shots="):
			_shots_dir = arg.trim_prefix("--shots=")

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
	var camera := Camera3D.new()
	camera.fov = 34.0
	add_child(camera)
	camera.position = Vector3(0.14, 1.0, 2.9)
	camera.look_at(Vector3(0.14, 0.93, 0.0))
	camera.current = true

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, 32, 0)
	sun.light_energy = 1.15
	sun.light_color = Color(1.0, 0.93, 0.82)
	sun.shadow_enabled = true
	add_child(sun)

	var fill := OmniLight3D.new()
	fill.position = Vector3(-0.9, 1.4, 1.6)
	fill.light_energy = 0.5
	fill.light_color = Color(0.75, 0.8, 1.0)
	fill.omni_range = 5.0
	add_child(fill)

	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.07, 0.05, 0.05)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.55, 0.5, 0.48)
	environment.ambient_light_energy = 0.55
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
	if _autotest:
		_run_autotest(delta)


# ---------------------------------------------------------------- self-test

## [seconds, what]: a key to press, or a note to print.
func _autotest_script() -> Array:
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
