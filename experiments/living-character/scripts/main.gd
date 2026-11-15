extends Node3D
## Demo startup: builds the scene, wires the layers together, handles keys,
## serves the web remote and draws the debug overlay.
##
## Command-line options (after `--`):
##   --seed=123        deterministic autonomous behaviour
##   --auto            start in autonomous mode
##   --camera=DEGREES  camera angle round the character (0 is straight on)
##   --no-overlay      hide the debug text
##   --no-web          do not start the web remote
##   --port=8002       port for the web remote
##   --review          play the review sequences, then quit
##   --trace=FILE      write head, hand and book positions every frame as CSV

const Config := preload("res://scripts/config.gd")
const Backdrop := preload("res://scripts/backdrop.gd")
const CharacterView := preload("res://scripts/character_view.gd")
const Stage := preload("res://scripts/stage.gd")
const MotorController := preload("res://scripts/motor_controller.gd")
const ActionScheduler := preload("res://scripts/action_scheduler.gd")
const BehaviourController := preload("res://scripts/behaviour_controller.gd")
const CharacterState := preload("res://scripts/character_state.gd")
const WebRemote := preload("res://scripts/web_remote.gd")

## Keyboard shortcuts. Each sends the same command name the web remote sends.
const KEYS := {
	KEY_1: "curious", KEY_2: "irritated", KEY_3: "tired", KEY_4: "read_book",
	KEY_5: "move_book", KEY_6: "frame_lifted", KEY_SPACE: "toggle_auto", KEY_R: "reset",
}

var stage: Node3D
var view: Node3D
var motor: Node
var scheduler: Node
var behaviour: Node
var state: RefCounted
var web: Node
var overlay: Label
var camera: Camera3D

var _camera_angle: float = Config.CAMERA_ANGLE
var _show_overlay := true
var _use_web := true
var _port: int = Config.WEB_PORT
var _trace: FileAccess
var _review := false
var _script: Array = []
var _clock := 0.0


func _ready() -> void:
	var seed_value := 0
	var start_auto := false
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			seed_value = int(arg.trim_prefix("--seed="))
		elif arg == "--auto":
			start_auto = true
		elif arg == "--review":
			_review = true
		elif arg.begins_with("--camera="):
			_camera_angle = float(arg.trim_prefix("--camera="))
		elif arg == "--no-overlay":
			_show_overlay = false
		elif arg == "--no-web":
			_use_web = false
		elif arg.begins_with("--port="):
			_port = int(arg.trim_prefix("--port="))
		elif arg.begins_with("--trace="):
			_trace = FileAccess.open(arg.trim_prefix("--trace="), FileAccess.WRITE)
			_trace.store_line("t,action,head_x,head_y,head_z,nose_x,nose_y,nose_z,hand_x,hand_y,hand_z,rhand_x,rhand_y,rhand_z,book_x,book_y,book_z,held")

	_build_world()
	stage = Stage.new()
	stage.name = "Stage"
	add_child(stage)
	# The edge of the picture on the character's right, at arm's depth: where
	# he grabs when the frame is moved. Taken from the camera, so it stays on
	# the visible edge whatever the camera angle.
	var screen := get_viewport().get_visible_rect().size
	stage.points["frame_edge_r"] = camera.project_position(Vector2(screen.x * 0.05, screen.y * 0.40), 2.6)

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
	behaviour.reset_requested.connect(reset)

	scheduler.action_started.connect(func(action_name: String) -> void:
		print("%7.2f  start  %s  (mood %s, fatigue %.2f)" % [_clock, action_name, state.mood, state.fatigue])
	)
	scheduler.action_ended.connect(func(action_name: String, completed: bool) -> void:
		print("%7.2f  %s  %s" % [_clock, "end  " if completed else "CUT  ", action_name])
	)

	_build_overlay()
	if _use_web:
		web = WebRemote.new()
		web.name = "WebRemote"
		web.command_handler = run_command
		web.status_provider = status
		add_child(web)
		if web.start(_port):
			print("Web remote on port %d. On the iPad open http://<this Mac's address>:%d" % [_port, _port])
		else:
			print("Web remote could not listen on port %d" % _port)
	if start_auto:
		behaviour.set_autonomous(true)
	if _review:
		_script = _review_script()


func _build_world() -> void:
	add_child(Backdrop.new())

	# The camera circles the character at a fixed distance and height.
	camera = Camera3D.new()
	camera.fov = 34.0
	add_child(camera)
	var aim := Vector3(0.14, 0.93, 0.0)
	var angle := deg_to_rad(_camera_angle)
	camera.position = aim + Vector3(sin(angle) * 2.9, 0.07, cos(angle) * 2.9)
	camera.look_at(aim)
	camera.current = true

	# Soft key from the front, with gentle shadows; a cool fill from the
	# other side; warm ambient.
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
	overlay.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	overlay.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	layer.add_child(overlay)
	layer.visible = _show_overlay


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			get_tree().quit()
		elif event.keycode == KEY_O:
			# The overlay is part of the picture, so it shows on the iPad too.
			_show_overlay = not _show_overlay
			overlay.get_parent().visible = _show_overlay
		elif KEYS.has(event.keycode):
			run_command(KEYS[event.keycode])


## Every input source ends up here: keyboard, web remote, review script.
func run_command(command_name: String) -> String:
	var reply: String = behaviour.command(command_name)
	print("%7.2f  cmd    %s -> %s" % [_clock, command_name, reply])
	return reply


## Back to a coherent home state: no actions, body at rest, book on the table.
func reset() -> void:
	scheduler.reset()
	motor.reset()
	stage.place_book_at_slot(stage.book_slot)
	state.reset()
	behaviour.set_autonomous(false)
	behaviour.reset()
	print("%7.2f  RESET" % _clock)


func status() -> Dictionary:
	return {
		"running": scheduler.running_names(), "queued": scheduler.queued_names(),
		"activity": state.activity, "mood": state.mood, "fatigue": snappedf(state.fatigue, 0.01),
		"attention": state.attention, "autonomous": behaviour.autonomous,
		"book_slot": stage.book_slot, "holding_book": motor.is_holding("l"),
		"last_command": behaviour.last_command,
		"stream_fps": web.stream_fps if web != null else 0.0,
		"encode_ms": snappedf(web.encode_ms, 0.1) if web != null else 0.0,
		"viewers": web.viewer_count() if web != null else 0,
		"render_fps": Engine.get_frames_per_second(),
	}


func _process(delta: float) -> void:
	_clock += delta
	var running: Array = scheduler.running_names()
	var queued: Array = scheduler.queued_names()
	if _show_overlay:
		overlay.text = "\n".join([
			"action     %s" % (", ".join(running) if not running.is_empty() else "none (asleep)"),
			"queued     %s" % (", ".join(queued) if not queued.is_empty() else "-"),
			"doing      %s" % state.activity,
			"mood       %s   fatigue %.2f   recent noises %d" % [state.mood, state.fatigue, state.stimulus_times.size()],
			"attention  %s" % state.attention,
			"command    %s" % behaviour.last_command,
			"autonomous %s%s" % ["ON" if behaviour.autonomous else "off", ("   seed %d" % behaviour.seed_value) if behaviour.seed_value != 0 else ""],
			"book       slot %d%s" % [stage.book_slot, "  (in hand)" if motor.is_holding("l") else ""],
			"web        %s" % (("port %d, %d viewer(s), %.0f fps" % [_port, web.viewer_count(), web.stream_fps]) if web != null else "off"),
			"",
			"1 curious  2 irritated  3 tired  4 book  5 move book  6 frame  Space auto  R reset",
		])
	if _trace != null:
		var eyes: Vector3 = view.eye_position()
		var nose: Vector3 = view.gaze_point()
		var hand_now: Vector3 = view.hand_position("l")
		var right_now: Vector3 = view.hand_position("r")
		var book_now: Vector3 = stage.book.global_position
		_trace.store_line("%.4f,%s,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%d" % [
			_clock, "+".join(running).replace(",", ";"), eyes.x, eyes.y, eyes.z, nose.x, nose.y, nose.z,
			hand_now.x, hand_now.y, hand_now.z, right_now.x, right_now.y, right_now.z,
			book_now.x, book_now.y, book_now.z, 1 if motor.is_holding("l") else 0])
	while not _script.is_empty() and _clock >= _script[0][0]:
		var entry: Array = _script.pop_front()
		if entry[1] == "quit":
			get_tree().quit()
		else:
			run_command(entry[1])


## [seconds, command]: the sequences for motion review, back to back.
func _review_script() -> Array:
	return [
		[4.0, "curious"], [15.0, "irritated"], [29.0, "tired"],
		[42.0, "read_book"],                              # near position
		[72.0, "move_book"], [73.5, "read_book"],         # far position
		[104.0, "frame_lifted"],                          # from sleep
		[116.0, "read_book"], [127.0, "frame_lifted"],    # while holding the book
		[140.0, "read_book"], [151.0, "curious"],         # noise while holding the book
		[172.0, "toggle_auto"], [204.0, "quit"],
	]
