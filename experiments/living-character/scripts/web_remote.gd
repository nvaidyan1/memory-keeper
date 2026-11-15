extends Node
## A very small HTTP server inside the game, for the iPad on the same network.
##
##   /                 the remote-control page (web/remote.html)
##   /cmd?name=X       runs a command through the same path as the keyboard
##   /status           current state as JSON
##   /stream           the live picture, as a stream of JPEG frames (MJPEG)
##   /snapshot.jpg     one frame
##
## No logic lives here or in the page: commands are passed straight to the
## handler it is given. There is no authentication; it is meant for a home
## network only.

const Config := preload("res://scripts/config.gd")

var command_handler: Callable      # func(name: String) -> String
var status_provider: Callable      # func() -> Dictionary

var frames_sent := 0
var encode_ms := 0.0               # running average time to grab and encode a frame
var stream_fps := 0.0              # measured, per viewer

var _server := TCPServer.new()
var _pending: Array = []           # connections whose request has not fully arrived
var _viewers: Array[StreamPeerTCP] = []
var _frame_wait := 0.0
var _fps_window := 0.0
var _fps_frames := 0
var _page := ""


func start(port: int) -> bool:
	_page = FileAccess.get_file_as_string("res://web/remote.html")
	return _server.listen(port) == OK


func viewer_count() -> int:
	return _viewers.size()


func _process(delta: float) -> void:
	while _server.is_connection_available():
		var peer := _server.take_connection()
		peer.set_no_delay(true)
		_pending.append({"peer": peer, "data": PackedByteArray(), "age": 0.0})

	for entry: Dictionary in _pending.duplicate():
		var peer: StreamPeerTCP = entry.peer
		peer.poll()
		entry.age += delta
		var waiting := peer.get_available_bytes()
		if waiting > 0:
			entry.data.append_array(peer.get_data(waiting)[1])
		var text: String = entry.data.get_string_from_utf8()
		if text.contains("\r\n\r\n"):
			_pending.erase(entry)
			_handle(text, peer)
		elif entry.age > 5.0 or peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			_pending.erase(entry)

	_fps_window += delta
	if _fps_window >= 2.0:
		stream_fps = _fps_frames / _fps_window
		_fps_window = 0.0
		_fps_frames = 0
	if _viewers.is_empty():
		return
	_frame_wait -= delta
	if _frame_wait <= 0.0:
		_frame_wait += 1.0 / Config.STREAM_FPS
		_frame_wait = maxf(_frame_wait, 0.0)
		_send_frame()


func _handle(request: String, peer: StreamPeerTCP) -> void:
	var parts := request.split(" ")
	var target := parts[1] if parts.size() > 1 else "/"
	var path := target.get_slice("?", 0)
	var query := target.get_slice("?", 1) if target.contains("?") else ""
	match path:
		"/":
			_reply(peer, "text/html; charset=utf-8", _page.to_utf8_buffer())
		"/cmd":
			var command_name := ""
			for pair: String in query.split("&"):
				if pair.begins_with("name="):
					command_name = pair.trim_prefix("name=").uri_decode()
			var answer: String = command_handler.call(command_name)
			_reply(peer, "application/json", JSON.stringify({"command": command_name, "reply": answer, "status": status_provider.call()}).to_utf8_buffer())
		"/status":
			_reply(peer, "application/json", JSON.stringify(status_provider.call()).to_utf8_buffer())
		"/snapshot.jpg":
			_reply(peer, "image/jpeg", _grab())
		"/stream":
			peer.put_data(("HTTP/1.1 200 OK\r\nContent-Type: multipart/x-mixed-replace; boundary=frame\r\n"
					+ "Cache-Control: no-store\r\nConnection: close\r\n\r\n").to_utf8_buffer())
			_viewers.append(peer)
		_:
			peer.put_data("HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".to_utf8_buffer())
			peer.disconnect_from_host()


func _reply(peer: StreamPeerTCP, content_type: String, body: PackedByteArray) -> void:
	var head := "HTTP/1.1 200 OK\r\nContent-Type: %s\r\nContent-Length: %d\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n" % [content_type, body.size()]
	peer.put_data(head.to_utf8_buffer())
	peer.put_data(body)
	peer.disconnect_from_host()


## The picture most recently drawn, as JPEG.
func _grab() -> PackedByteArray:
	var started := Time.get_ticks_usec()
	var jpeg := get_viewport().get_texture().get_image().save_jpg_to_buffer(Config.STREAM_QUALITY)
	var took := (Time.get_ticks_usec() - started) / 1000.0
	encode_ms = took if encode_ms == 0.0 else lerpf(encode_ms, took, 0.1)
	return jpeg


func _send_frame() -> void:
	var jpeg := _grab()
	# X-Sent carries the Mac's clock in milliseconds, so a client on the same
	# machine can measure how old a frame is when it arrives.
	var head := ("--frame\r\nContent-Type: image/jpeg\r\nContent-Length: %d\r\nX-Sent: %d\r\n\r\n" % [jpeg.size(), Time.get_ticks_msec()]).to_utf8_buffer()
	for peer: StreamPeerTCP in _viewers.duplicate():
		peer.poll()
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED or peer.put_data(head) != OK or peer.put_data(jpeg) != OK or peer.put_data("\r\n".to_utf8_buffer()) != OK:
			_viewers.erase(peer)
	frames_sent += 1
	_fps_frames += 1
