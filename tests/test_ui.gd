extends SceneTree

const MAIN := preload("res://scenes/main.tscn")
var issues := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(yes: bool, message: String) -> void:
	if not yes:
		issues += 1
		push_error(message)


func _run() -> void:
	var app: Node2D = MAIN.instantiate()
	root.add_child(app)
	await process_frame
	_check(not app.puzzle.is_empty(), "No immediate board on first install")
	_check(int(app.puzzle["size"]) == 6, "First puzzle should be easy")
	var idx: int = app._index_at(Vector2(107, 460))
	_check(idx >= 0, "Board hit-test invalid")
	app._tap(Vector2(420, 368)) # select manual X mode
	_check(app.mode == 2, "Manual X button did not select")
	app._tap(Vector2(107, 460))
	_check(app.marks[idx] == 2, "First tap did not mark an X")
	app._tap(Vector2(107, 460))
	_check(app.marks[idx] == 0, "Second tap did not remove X")
	app._tap(Vector2(100, 367)) # select cat mode
	_check(app.mode == 1, "Cat button did not select")
	app._tap(Vector2(107, 460))
	_check(app.marks[idx] == 1, "Cat mode did not mark a cat")
	app._tap(Vector2(107, 460))
	_check(app.marks[idx] == 0, "Second cat tap did not remove a cat")
	app._pointer_down(Vector2(107, 460))
	app._down_ms = Time.get_ticks_msec() - 600
	app._mouse_held = true
	app._process(0.016)
	app._mouse_held = false
	app._pointer_up(Vector2(107, 460), false)
	_check(app.marks[idx] == 2, "Long press should mark X and not toggle into cat")
	app._undo()
	_check(app.marks[idx] == 0, "Undo did not restore previous mark")
	app._tap(Vector2(600, 1200))
	_check(app.auto_x, "Auto-X toggle did not work")
	app._tap(Vector2(265, 190)) # medium difficulty selection
	_check(app.selected_level == "medium", "Difficulty toggle did not work")
	app._tap(Vector2(350, 278)) # NEW GAME
	_check(int(app.puzzle["size"]) == 7, "New game did not consume a medium puzzle")
	app._save_progress()
	_check(FileAccess.file_exists(app.PROGRESS_PATH), "Progress is not saved")
	app.queue_free()
	await process_frame
	print("UI: mode, mark, long-press, undo, auto-X, level, save tested; %d failures" % issues)
	quit(0 if issues == 0 else 1)
