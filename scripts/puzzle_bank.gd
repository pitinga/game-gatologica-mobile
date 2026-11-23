extends Node
## Queue of five certified boards per difficulty, three emergency boards per
## difficulty, persistent history and a single throttled CPU worker. The worker
## never interacts with the scene tree, draws or writes files.

const RULES := preload("res://scripts/puzzle_rules.gd")
const LEVELS := ["easy", "medium", "hard"]
const TARGET := 5
const SAVE_PATH := "user://gatologica_bank_v2.json"
const STARTER_PATH := "res://data/starter_puzzles.json"

var _pool: Dictionary = {"easy": [], "medium": [], "hard": []}
var _emergency: Dictionary = {"easy": [], "medium": [], "hard": []}
var _history: Array = []
var _known: Dictionary = {}
var _validator = RULES.new()
var _mutex := Mutex.new()
var _thread := Thread.new()
var _running := true
var _active := false
var _recent_touch_ms := 0
var _preferred := "easy"
var _dirty := false
var _last_save_ms := 0


func _ready() -> void:
	if not _load():
		_install_starter()
	_thread.start(Callable(self, "_worker_loop"))


func _install_starter() -> void:
	var raw = JSON.parse_string(FileAccess.get_file_as_string(STARTER_PATH))
	if typeof(raw) != TYPE_DICTIONARY or not raw.has("puzzles"):
		push_error("Starter pack missing")
		return
	for level in LEVELS:
		var accepted := 0
		for puzzle in raw["puzzles"].get(level, []):
			if not _validator.approved(puzzle):
				push_error("Uncertified starter puzzle: %s" % level)
				continue
			var sign: String = _validator.signature(puzzle)
			if _known.has(sign):
				continue
			_known[sign] = true
			_history.append(sign)
			if accepted < TARGET:
				_pool[level].append(puzzle)
			else:
				_emergency[level].append(puzzle)
			accepted += 1
	_dirty = true
	_save()


func _load() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var raw = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if typeof(raw) != TYPE_DICTIONARY or int(raw.get("version", -1)) != 2:
		return false
	if typeof(raw.get("pool")) != TYPE_DICTIONARY or typeof(raw.get("emergency")) != TYPE_DICTIONARY:
		return false
	var clean_pool: Dictionary = {}
	var clean_emergency: Dictionary = {}
	for level in LEVELS:
		var available: Array = raw["pool"].get(level, [])
		var standby: Array = raw["emergency"].get(level, [])
		if available.size() > TARGET or standby.size() > 3:
			return false
		for puzzle in available + standby:
			if not _validator.approved(puzzle) or int(puzzle["size"]) != int(RULES.LEVEL_SIZES[level]):
				return false
		clean_pool[level] = available
		clean_emergency[level] = standby
	_pool = clean_pool
	_emergency = clean_emergency
	_history = raw.get("history", [])
	if typeof(_history) != TYPE_ARRAY:
		_history = []
	for value in _history:
		_known[str(value)] = true
	for level in LEVELS:
		for puzzle in _pool[level] + _emergency[level]:
			var sign := _validator.signature(puzzle)
			if not _known.has(sign):
				_known[sign] = true
				_history.append(sign)
	return true


func use_game(level: String) -> Dictionary:
	if not LEVELS.has(level):
		return {}
	_mutex.lock()
	var board: Dictionary = {}
	if not _pool[level].is_empty():
		board = _pool[level].pop_front()
	elif not _emergency[level].is_empty():
		board = _emergency[level].pop_front()
	_preferred = level
	if not board.is_empty():
		_dirty = true
	_mutex.unlock()
	if not board.is_empty():
		_save()
	return board


func counts() -> Dictionary:
	_mutex.lock()
	var data: Dictionary = {}
	for level in LEVELS:
		data[level] = _pool[level].size()
	_mutex.unlock()
	return data


func set_generation_enabled(enabled: bool) -> void:
	_mutex.lock()
	_active = enabled
	_mutex.unlock()


func notify_touch() -> void:
	_mutex.lock()
	_recent_touch_ms = Time.get_ticks_msec()
	_mutex.unlock()


func _worker_loop() -> void:
	var generator = RULES.new()
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	while true:
		_mutex.lock()
		var running: bool = _running
		var enabled: bool = _active
		var last_touch: int = _recent_touch_ms
		var preference: String = _preferred
		var levels: Array = LEVELS.duplicate()
		levels.sort_custom(func(a, b): return int(_pool[a].size()) < int(_pool[b].size()))
		if _pool[preference].size() < TARGET:
			levels.erase(preference)
			levels.push_front(preference)
		var wanted := ""
		for level in levels:
			if _pool[level].size() < TARGET:
				wanted = level
				break
		_mutex.unlock()
		if not running:
			break
		if not enabled or wanted.is_empty() or Time.get_ticks_msec() - last_touch < 450:
			OS.delay_msec(150)
			continue
		## Small generation batches prevent a long uninterruptible operation.
		var puzzle: Dictionary = generator.generate(wanted, rng, 12)
		if not puzzle.is_empty():
			var sign: String = generator.signature(puzzle)
			_mutex.lock()
			if _pool[wanted].size() < TARGET and not _known.has(sign):
				_pool[wanted].append(puzzle)
				_known[sign] = true
				_history.append(sign)
				_dirty = true
				if _history.size() > 2000:
					var oldest: String = str(_history.pop_front())
					_known.erase(oldest)
			_mutex.unlock()
		OS.delay_msec(30)


func _process(_delta: float) -> void:
	if Time.get_ticks_msec() - _last_save_ms > 1500:
		_save()


func _save() -> void:
	_mutex.lock()
	if not _dirty:
		_mutex.unlock()
		return
	var data := {"version": 2, "pool": _pool.duplicate(true), "emergency": _emergency.duplicate(true), "history": _history.duplicate()}
	_dirty = false
	_mutex.unlock()
	var temp := SAVE_PATH + ".tmp"
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		_mutex.lock()
		_dirty = true
		_mutex.unlock()
		return
	file.store_string(JSON.stringify(data))
	file.close()
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(temp), ProjectSettings.globalize_path(SAVE_PATH)) != OK:
		_mutex.lock()
		_dirty = true
		_mutex.unlock()
	_last_save_ms = Time.get_ticks_msec()


func _exit_tree() -> void:
	_mutex.lock()
	_running = false
	_mutex.unlock()
	if _thread.is_started():
		_thread.wait_to_finish()
	_save()
