extends Node2D
## Portrait-first, no external art/fonts. Accessible manual X and cat modes;
## optional computed X never overwrites or persists manual marks.

const RULES := preload("res://scripts/puzzle_rules.gd")
const BANK := preload("res://scripts/puzzle_bank.gd")
const PROGRESS_PATH := "user://gatologica_progress_v1.json"
const W := 720.0
const H := 1280.0
const BOARD := Rect2(32, 353, 656, 656)
const BG := Color("#f5f6fb")
const INK := Color("#293044")
const MUTED := Color("#68738a")
const DARK := Color("#373757")
const WHITE := Color("#ffffff")
const PURPLE := Color("#7362cb")
const PINK := Color("#f4b5cc")
const BORDER := Color("#e2e5ef")
const PALETTE := ["#f7c6d2", "#fff0b2", "#c9e7fc", "#c9eacb", "#d9cbfa", "#ffd8af", "#c0e5e1", "#f2d0f3"]
const DIFFICULTIES := ["easy", "medium", "hard"]
const DIFFICULTY_NAMES := {"easy": "Fácil", "medium": "Médio", "hard": "Difícil"}

var rules = RULES.new()
var bank: Node
var selected_level := "easy"
var current_level := "easy"
var puzzle: Dictionary = {}
var marks := PackedInt32Array()
var undo_stack: Array = []
var mode := 1 # 1 = cat, 2 = manual block
var auto_x := false
var elapsed := 0.0
var won := false
var paused := false
var help_open := false
var waiting := false
var notice := "Encontre um gato por linha, coluna e cor."
var hint_cell := -1
var hint_until_ms := 0
var _active_finger := -1
var _down_pos := Vector2.ZERO
var _down_ms := 0
var _dragged := false
var _long_done := false
var _mouse_held := false
var _last_draw_ms := 0
var _last_save_ms := 0
var _dirty := false
var _focused := true


func _ready() -> void:
	bank = BANK.new()
	add_child(bank)
	if not _load_progress():
		_start_new_game("easy")
	bank.set_generation_enabled(not won and not paused and _focused)
	queue_redraw()


func _process(delta: float) -> void:
	if not puzzle.is_empty() and not won and not paused and not help_open:
		var before := int(elapsed)
		elapsed += minf(delta, 0.1)
		if int(elapsed) != before:
			_dirty = true
	if waiting:
		var available: Dictionary = bank.counts()
		if int(available.get(selected_level, 0)) > 0:
			_start_new_game(selected_level)
	if _active_finger >= 0 or _mouse_held:
		if not _dragged and not _long_done and Time.get_ticks_msec() - _down_ms >= 450:
			var cell := _index_at(_down_pos)
			if cell >= 0 and not won and not paused and not help_open:
				_apply_mark(cell, 2)
				_long_done = true
	if _dirty and Time.get_ticks_msec() - _last_save_ms > 5000:
		_save_progress()
	if Time.get_ticks_msec() - _last_draw_ms > 300:
		_last_draw_ms = Time.get_ticks_msec()
		queue_redraw()


func _draw() -> void:
	var viewport := get_viewport_rect().size
	var factor := minf(viewport.x / W, viewport.y / H)
	var offset := (viewport - Vector2(W, H) * factor) * 0.5
	draw_set_transform(offset, 0, Vector2.ONE * factor)
	draw_rect(Rect2(0, 0, W, H), BG)
	_rounded(Rect2(18, 18, 684, 117), WHITE, 23)
	_label("GatoLógica", Vector2(360, 64), 49, INK)
	_label("PUZZLE DE CORES  •  SEM ADIVINHAR", Vector2(360, 107), 18, MUTED)
	_label("ESCOLHA A DIFICULDADE", Vector2(360, 161), 18, MUTED)
	for i in range(3):
		var box := Rect2(33 + 222 * i, 177, 210, 57)
		_button(box, DIFFICULTY_NAMES[DIFFICULTIES[i]], selected_level == DIFFICULTIES[i], 25)
	_button(Rect2(34, 249, 651, 62), "NOVO JOGO", true, 29)
	_rounded(Rect2(32, 325, 656, 16), Color("#dee2ef"), 8)
	_button(Rect2(32, 351 - 4, 322, 51), "GATO", mode == 1, 23)
	_button(Rect2(365, 351 - 4, 323, 51), "X  BLOQUEAR", mode == 2, 23)
	# The board is intentionally below mode buttons; no hidden controls below fold.
	_draw_board()
	var count := bank.counts()
	var remaining := 0
	for x in marks:
		if x == 1:
			remaining += 1
	var status := "Gatos: %d/%d    •    Tempo: %s    •    Reserva: %d/5" % [remaining, int(puzzle.get("size", 6)), _timer_text(), int(count.get(current_level, 0))]
	_label(status, Vector2(360, 1059), 22, INK)
	_button(Rect2(33, 1090, 209, 58), "DESFAZER", false, 22)
	_button(Rect2(255, 1090, 209, 58), "DICA", false, 22)
	_button(Rect2(477, 1090, 209, 58), "REGRAS", false, 22)
	_rounded(Rect2(33, 1164, 654, 77), WHITE, 16)
	_label("X automático", Vector2(200, 1202), 25, INK)
	_label("(opcional)", Vector2(368, 1202), 19, MUTED)
	_rounded(Rect2(586, 1184, 80, 38), Color("#8d80d9") if auto_x else Color("#c8ccd9"), 19)
	draw_circle(Vector2(643 if auto_x else 608, 1203), 15, WHITE)
	if help_open:
		_draw_help()
	elif won:
		_draw_win()
	elif waiting:
		_rounded(Rect2(57, 468, 606, 295), DARK, 24)
		_label("Preparando novo desafio...", Vector2(360, 574), 30, WHITE)
		_label("O gerador está repondo a reserva.", Vector2(360, 630), 22, WHITE)
		draw_circle(Vector2(360, 693), 16, PINK)
	draw_set_transform(Vector2.ZERO)


func _draw_board() -> void:
	var n := int(puzzle.get("size", 6))
	_rounded(Rect2(22, 404, 676, 616), Color("#e2e5ef"), 20)
	if puzzle.is_empty():
		return
	# The board is square; bottom elements fit within the 1280px viewport.
	var board := Rect2(34, 411, 652, 596)
	var cell_size := minf(board.size.x, board.size.y) / n
	var side := cell_size * n
	var origin := Vector2(360 - side * 0.5, board.position.y + (board.size.y - side) * 0.5)
	var regions: Array = puzzle["regions"]
	var auto_marks := rules.auto_exclusions(puzzle, marks) if auto_x else PackedByteArray()
	for row in range(n):
		for col in range(n):
			var i := row * n + col
			var pos := origin + Vector2(col, row) * cell_size
			var rect := Rect2(pos + Vector2(1, 1), Vector2.ONE * (cell_size - 2))
			_rounded(rect, Color(PALETTE[int(regions[i])]), 5)
			var center := pos + Vector2.ONE * (cell_size * 0.5)
			if marks[i] == 1:
				_draw_cat(center, cell_size)
			elif marks[i] == 2:
				_draw_x(center, cell_size, Color("#374259"), 5.5)
			elif auto_x and auto_marks[i] == 1:
				_draw_x(center, cell_size, Color("#6b708c", 0.48), 3)
			if hint_cell == i and Time.get_ticks_msec() < hint_until_ms:
				draw_arc(center, cell_size * 0.40, 0, TAU, 40, PURPLE, 5, true)
	for row in range(n):
		for col in range(n):
			var i := row * n + col
			var here: int = int(regions[i])
			var p := origin + Vector2(col, row) * cell_size
			var line := Color("#494960")
			if col == 0 or here != int(regions[i - 1]):
				draw_line(p, p + Vector2(0, cell_size), line, 4, true)
			if row == 0 or here != int(regions[i - n]):
				draw_line(p, p + Vector2(cell_size, 0), line, 4, true)
			if col == n - 1:
				draw_line(p + Vector2(cell_size, 0), p + Vector2(cell_size, cell_size), line, 4, true)
			if row == n - 1:
				draw_line(p + Vector2(0, cell_size), p + Vector2(cell_size, cell_size), line, 4, true)
	_label(notice, Vector2(360, 1031), 18, MUTED)


func _draw_cat(center: Vector2, side: float) -> void:
	var scale := side * 0.55
	var fill := Color("#4b455b")
	var left_ear := PackedVector2Array([center + Vector2(-0.35, -0.18) * scale, center + Vector2(-0.32, -0.65) * scale, center + Vector2(-0.02, -0.34) * scale])
	var right_ear := PackedVector2Array([center + Vector2(0.35, -0.18) * scale, center + Vector2(0.32, -0.65) * scale, center + Vector2(0.02, -0.34) * scale])
	draw_colored_polygon(left_ear, fill)
	draw_colored_polygon(right_ear, fill)
	draw_circle(center + Vector2(0, 0.05) * scale, scale * 0.42, fill)
	draw_circle(center + Vector2(-0.17, -0.01) * scale, scale * 0.06, WHITE)
	draw_circle(center + Vector2(0.17, -0.01) * scale, scale * 0.06, WHITE)
	draw_circle(center + Vector2(0, 0.17) * scale, scale * 0.07, PINK)
	for direction in [-1, 1]:
		for rise in [-1, 1]:
			var a := center + Vector2(direction * 0.22, 0.17) * scale
			var b := center + Vector2(direction * 0.59, 0.17 + rise * 0.12) * scale
			draw_line(a, b, fill, 2, true)


func _draw_x(center: Vector2, side: float, color: Color, width: float) -> void:
	var radius := side * 0.19
	draw_line(center - Vector2.ONE * radius, center + Vector2.ONE * radius, color, width, true)
	draw_line(center + Vector2(-radius, radius), center + Vector2(radius, -radius), color, width, true)


func _draw_help() -> void:
	_rounded(Rect2(45, 377, 630, 550), DARK, 25)
	_label("Como jogar", Vector2(360, 443), 40, WHITE)
	_label("1 gato em cada linha", Vector2(360, 511), 27, WHITE)
	_label("1 gato em cada coluna", Vector2(360, 560), 27, WHITE)
	_label("1 gato em cada região colorida", Vector2(360, 609), 27, WHITE)
	_label("Gatos não se tocam, nem na diagonal", Vector2(360, 658), 23, WHITE)
	_label("Selecione GATO ou X BLOQUEAR.", Vector2(360, 722), 23, WHITE)
	_label("Segure uma casa para colocar X.", Vector2(360, 760), 23, WHITE)
	_label("As fases são resolvidas sem adivinhação.", Vector2(360, 804), 20, WHITE)
	_button(Rect2(100, 845, 520, 60), "ENTENDI", true, 26)


func _draw_win() -> void:
	_rounded(Rect2(45, 470, 630, 326), DARK, 25)
	_label("PARABÉNS!", Vector2(360, 556), 44, WHITE)
	_label("Você resolveu por lógica!", Vector2(360, 615), 26, WHITE)
	_label("Tempo: %s" % _timer_text(), Vector2(360, 668), 25, WHITE)
	_button(Rect2(103, 704, 514, 63), "PRÓXIMO DESAFIO", true, 25)


func _rounded(rect: Rect2, fill: Color, radius: int) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.set_corner_radius_all(radius)
	draw_style_box(style, rect)


func _label(value: String, center: Vector2, size: int, color: Color) -> void:
	var font := ThemeDB.fallback_font
	var text_width := font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_string(font, center + Vector2(-text_width * 0.5, size * 0.35), value, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


func _button(rect: Rect2, value: String, selected: bool, font_size: int) -> void:
	_rounded(rect, PURPLE if selected else WHITE, 17)
	_label(value, rect.get_center(), font_size, WHITE if selected else INK)


func _timer_text() -> String:
	var seconds := int(elapsed)
	return "%02d:%02d" % [seconds / 60, seconds % 60]


func _to_local(pos: Vector2) -> Vector2:
	var view := get_viewport_rect().size
	var factor := minf(view.x / W, view.y / H)
	return (pos - (view - Vector2(W, H) * factor) * 0.5) / factor


func _index_at(pos: Vector2) -> int:
	if puzzle.is_empty():
		return -1
	var n := int(puzzle["size"])
	var board := Rect2(34, 411, 652, 596)
	var cell_size := minf(board.size.x, board.size.y) / n
	var side := cell_size * n
	var origin := Vector2(360 - side * 0.5, board.position.y + (board.size.y - side) * 0.5)
	var inside := Rect2(origin, Vector2.ONE * side)
	if not inside.has_point(pos):
		return -1
	var col := clampi(int((pos.x - origin.x) / cell_size), 0, n - 1)
	var row := clampi(int((pos.y - origin.y) / cell_size), 0, n - 1)
	return row * n + col


func _tap(pos: Vector2) -> void:
	if help_open:
		if Rect2(100, 845, 520, 60).has_point(pos):
			help_open = false
			bank.set_generation_enabled(not won and not paused and _focused)
			queue_redraw()
		return
	if won:
		if Rect2(103, 704, 514, 63).has_point(pos):
			_start_new_game(selected_level)
		return
	if waiting:
		return
	for i in range(3):
		if Rect2(33 + 222 * i, 177, 210, 57).has_point(pos):
			selected_level = DIFFICULTIES[i]
			notice = "Toque NOVO JOGO para iniciar %s." % DIFFICULTY_NAMES[selected_level]
			_dirty = true
			queue_redraw()
			return
	if Rect2(34, 249, 651, 62).has_point(pos):
		_start_new_game(selected_level)
		return
	if Rect2(32, 347, 322, 51).has_point(pos):
		mode = 1
	elif Rect2(365, 347, 323, 51).has_point(pos):
		mode = 2
	elif Rect2(33, 1090, 209, 58).has_point(pos):
		_undo()
	elif Rect2(255, 1090, 209, 58).has_point(pos):
		_hint()
	elif Rect2(477, 1090, 209, 58).has_point(pos):
		help_open = true
		bank.set_generation_enabled(false)
	elif Rect2(33, 1164, 654, 77).has_point(pos):
		auto_x = not auto_x
		_dirty = true
	else:
		var index := _index_at(pos)
		if index >= 0:
			_apply_mark(index, mode)
	_dirty = true
	queue_redraw()


func _apply_mark(index: int, requested: int) -> void:
	if puzzle.is_empty() or won or index < 0 or index >= marks.size():
		return
	undo_stack.append(marks.duplicate())
	if undo_stack.size() > 100:
		undo_stack.pop_front()
	marks[index] = 0 if marks[index] == requested else requested
	won = rules.is_win(puzzle, marks)
	if won:
		bank.set_generation_enabled(false)
		notice = "Desafio concluído!"
	else:
		notice = "Toque novamente para remover uma marca."
	_dirty = true
	queue_redraw()


func _undo() -> void:
	if undo_stack.is_empty():
		return
	marks = undo_stack.pop_back()
	won = false
	notice = "Última marcação desfeita."
	bank.set_generation_enabled(not paused and _focused)
	_dirty = true
	queue_redraw()


func _hint() -> void:
	if puzzle.is_empty():
		return
	var proof: Dictionary = rules.solve_by_deduction(puzzle)
	if not bool(proof.get("solved", false)):
		notice = "Desafio não validado: dica indisponível."
		return
	for value in proof["forced"]:
		var i := int(value)
		if marks[i] == 1:
			continue
		hint_cell = i
		hint_until_ms = Time.get_ticks_msec() + 4000
		notice = "Observe a casa destacada: ela é obrigatória."
		if marks[i] == 2:
			notice = "Revise o X na casa destacada."
		queue_redraw()
		return
	notice = "Confira seus gatos e os possíveis conflitos."
	queue_redraw()


func _start_new_game(level: String) -> void:
	var next_board: Dictionary = bank.use_game(level)
	if next_board.is_empty():
		waiting = true
		selected_level = level
		bank.set_generation_enabled(true)
		queue_redraw()
		return
	waiting = false
	puzzle = next_board
	selected_level = level
	current_level = level
	marks.resize(int(puzzle["size"]) * int(puzzle["size"]))
	marks.fill(0)
	undo_stack.clear()
	elapsed = 0
	won = false
	paused = false
	help_open = false
	hint_cell = -1
	notice = "1 gato por linha, coluna e região de cor."
	bank.set_generation_enabled(_focused)
	_dirty = true
	_save_progress()
	queue_redraw()


func _save_progress() -> void:
	if puzzle.is_empty():
		return
	var saved_marks: Array = []
	for value in marks:
		saved_marks.append(value)
	var data := {"version": 1, "puzzle": puzzle, "marks": saved_marks, "level": current_level, "selected": selected_level, "mode": mode, "auto_x": auto_x, "elapsed": elapsed, "won": won}
	var temp := PROGRESS_PATH + ".tmp"
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(data))
	file.close()
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(temp), ProjectSettings.globalize_path(PROGRESS_PATH)) == OK:
		_dirty = false
		_last_save_ms = Time.get_ticks_msec()


func _load_progress() -> bool:
	if not FileAccess.file_exists(PROGRESS_PATH):
		return false
	var data = JSON.parse_string(FileAccess.get_file_as_string(PROGRESS_PATH))
	if typeof(data) != TYPE_DICTIONARY or int(data.get("version", 0)) != 1:
		return false
	var board: Dictionary = data.get("puzzle", {})
	if not rules.approved(board):
		return false
	var values: Array = data.get("marks", [])
	if values.size() != int(board["size"]) * int(board["size"]):
		return false
	var restored := PackedInt32Array()
	for value in values:
		if int(value) < 0 or int(value) > 2:
			return false
		restored.append(int(value))
	puzzle = board
	marks = restored
	current_level = str(data.get("level", "easy"))
	selected_level = str(data.get("selected", current_level))
	if not DIFFICULTIES.has(current_level) or not DIFFICULTIES.has(selected_level) or int(board["size"]) != int(RULES.LEVEL_SIZES[current_level]):
		return false
	mode = clampi(int(data.get("mode", 1)), 1, 2)
	auto_x = bool(data.get("auto_x", false))
	elapsed = maxf(0, float(data.get("elapsed", 0)))
	won = rules.is_win(puzzle, marks)
	notice = "Partida recuperada. Bom jogo!"
	return true


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_focused = false
		if is_instance_valid(bank):
			bank.set_generation_enabled(false)
		_save_progress()
	elif what == NOTIFICATION_APPLICATION_RESUMED or what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_focused = true
		if is_instance_valid(bank):
			bank.set_generation_enabled(not won and not help_open)
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST:
		help_open = false
		_save_progress()
		queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and _active_finger < 0:
			_active_finger = event.index
			_pointer_down(_to_local(event.position))
		elif not event.pressed and event.index == _active_finger:
			_pointer_up(_to_local(event.position), bool(event.canceled))
			_active_finger = -1
	elif event is InputEventScreenDrag and event.index == _active_finger:
		if _to_local(event.position).distance_to(_down_pos) > 18:
			_dragged = true
	elif event is InputEventMouseButton and not OS.has_feature("mobile"):
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			var cell := _index_at(_to_local(event.position))
			if cell >= 0:
				_apply_mark(cell, 2)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_mouse_held = true
				_pointer_down(_to_local(event.position))
			else:
				_mouse_held = false
				_pointer_up(_to_local(event.position), false)
	elif event is InputEventMouseMotion and _mouse_held and not OS.has_feature("mobile"):
		if _to_local(event.position).distance_to(_down_pos) > 18:
			_dragged = true


func _pointer_down(pos: Vector2) -> void:
	_down_pos = pos
	_down_ms = Time.get_ticks_msec()
	_dragged = false
	_long_done = false
	bank.notify_touch()


func _pointer_up(pos: Vector2, canceled: bool) -> void:
	bank.notify_touch()
	if not canceled and not _dragged and not _long_done and pos.distance_to(_down_pos) < 26:
		_tap(pos)
	_long_done = false
