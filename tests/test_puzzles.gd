extends SceneTree

const RULES := preload("res://scripts/puzzle_rules.gd")
const STARTER := "res://data/starter_puzzles.json"
var issues := 0


func _initialize() -> void:
	print("Starting certified puzzle regression checks")
	_run()


func _check(yes: bool, message: String) -> void:
	if not yes:
		issues += 1
		push_error(message)


func _run() -> void:
	var solver = RULES.new()
	var raw = JSON.parse_string(FileAccess.get_file_as_string(STARTER))
	_check(typeof(raw) == TYPE_DICTIONARY, "Starter JSON missing")
	if typeof(raw) != TYPE_DICTIONARY:
		quit(1)
		return
	var all_signatures: Dictionary = {}
	for level in ["easy", "medium", "hard"]:
		print("Checking starter level: ", level)
		var boards: Array = raw["puzzles"][level]
		_check(boards.size() >= 8, "%s needs 5 active and 3 emergency boards" % level)
		for board in boards:
			_check(solver.valid_shape(board), "Invalid connected color partition in %s" % level)
			_check(int(board["size"]) == int(RULES.LEVEL_SIZES[level]), "Incorrect board dimensions in %s" % level)
			_check(solver.count_solutions(board) == 1, "Puzzle has zero or multiple solutions: %s" % level)
			var proof: Dictionary = solver.solve_by_deduction(board)
			_check(bool(proof.get("solved", false)), "Requires guesses: %s" % level)
			_check(proof.get("forced", []).size() == int(board["size"]), "Proof is incomplete: %s" % level)
			var marks := PackedInt32Array()
			marks.resize(int(board["size"]) * int(board["size"]))
			for index in proof.get("forced", []):
				marks[int(index)] = 1
			_check(solver.is_win(board, marks), "Deduction proof violates a game rule: %s" % level)
			var key: String = solver.signature(board)
			_check(not all_signatures.has(key), "Duplicated startup game")
			all_signatures[key] = true
			var cats := 0
			for index in range(marks.size()):
				if marks[index] == 1:
					cats += 1
			_check(cats == int(board["size"]), "Wrong number of forced cats")
			var excluded: PackedByteArray = solver.auto_exclusions(board, marks)
			for index in range(marks.size()):
				if marks[index] == 1:
					_check(excluded[index] == 0, "Auto-X overwrote a cat")
				elif marks[index] == 0:
					_check(excluded[index] == 1, "Solved board has an available empty cell")
			marks[int(proof["forced"][0])] = 2
			_check(not solver.is_win(board, marks), "Incorrect marks must not win")
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261123
	for level in ["easy", "medium", "hard"]:
		print("Checking procedural generation: ", level)
		var generated: Dictionary = solver.generate(level, rng, 3200)
		_check(not generated.is_empty(), "Runtime generator failed to produce %s" % level)
		if not generated.is_empty():
			_check(solver.approved(generated), "Runtime generator admitted an invalid board: %s" % level)
	print("Rules: %d starter boards validated; %d failures" % [all_signatures.size(), issues])
	quit(0 if issues == 0 else 1)
