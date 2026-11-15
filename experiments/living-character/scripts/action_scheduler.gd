extends Node
## Runs actions and keeps them from fighting over the body.
##
## An action is a Dictionary:
##   name           String
##   resources      Array of body parts it needs ("head", "face", "torso", "arm_l", "prop", ...)
##   priority       int; a higher priority may interrupt a lower one
##   interruptible  bool
##   steps          Array of Callables. Each starts some movement and returns the
##                  seconds to wait before the next step. Returning a negative
##                  number abandons the action.
##   on_end         optional Callable(completed: bool), called once when the action
##                  finishes, is abandoned or is interrupted. It may return a
##                  follow-up action (for example "put the book back").
##
## Actions whose resources do not overlap run side by side. Conflicting ones
## are queued, unless the newcomer outranks an interruptible action.

signal action_started(action_name: String)
signal action_ended(action_name: String, completed: bool)

const MAX_QUEUE := 3

var _running := {}    # id -> action
var _queue: Array[Dictionary] = []
var _next_id := 1


func is_busy() -> bool:
	return not _running.is_empty() or not _queue.is_empty()


func running_names() -> Array:
	var names := []
	for action: Dictionary in _running.values():
		names.append(action.name)
	return names


func queued_names() -> Array:
	var names := []
	for action: Dictionary in _queue:
		names.append(action.name)
	return names


func owns(resource: String) -> bool:
	for action: Dictionary in _running.values():
		if resource in action.resources:
			return true
	return false


## Starts the action now, interrupts for it, or queues it.
## Returns "started", "interrupted others", "queued" or "dropped".
func request(action: Dictionary) -> String:
	var conflicts := _conflicts(action)
	if conflicts.is_empty():
		_start(action)
		return "started"
	var can_interrupt := true
	for id: int in conflicts:
		var other: Dictionary = _running[id]
		if not other.get("interruptible", true) or other.get("priority", 0) >= action.get("priority", 0):
			can_interrupt = false
	if can_interrupt:
		for id: int in conflicts:
			_end(id, false)
		# Follow-ups from the interrupted actions are now queued; the newcomer goes first.
		_start(action)
		return "interrupted others"
	if _queue.size() >= MAX_QUEUE:
		return "dropped"
	for queued: Dictionary in _queue:
		if queued.name == action.name:
			return "dropped"
	_queue.append(action)
	return "queued"


## Forgets everything immediately. Running steps stop at their next check.
func reset() -> void:
	_running.clear()
	_queue.clear()


func _conflicts(action: Dictionary) -> Array:
	var ids := []
	for id: int in _running:
		for resource: String in action.resources:
			if resource in _running[id].resources:
				ids.append(id)
				break
	return ids


func _start(action: Dictionary) -> void:
	var id := _next_id
	_next_id += 1
	_running[id] = action
	action_started.emit(action.name)
	_run(id, action)


func _run(id: int, action: Dictionary) -> void:
	for step: Callable in action.steps:
		var seconds: float = step.call()
		if seconds < 0.0:
			_end(id, false)
			return
		if seconds > 0.0:
			await get_tree().create_timer(seconds).timeout
		# Interrupted or reset while waiting: stop without touching anything.
		if not _running.has(id):
			return
	_end(id, true)


func _end(id: int, completed: bool) -> void:
	var action: Dictionary = _running[id]
	_running.erase(id)
	action_ended.emit(action.name, completed)
	if action.has("on_end"):
		var follow_up: Variant = action.on_end.call(completed)
		if follow_up is Dictionary:
			_queue.push_front(follow_up)
	_drain.call_deferred()


func _drain() -> void:
	var waiting := _queue.duplicate()
	_queue.clear()
	for action: Dictionary in waiting:
		if _conflicts(action).is_empty():
			_start(action)
		else:
			_queue.append(action)
