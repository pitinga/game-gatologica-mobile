extends RefCounted
## All checks use only the public rules: exactly one cat per row/column/colour,
## and cats may not touch, including diagonally. The deduction solver never
## receives a hidden solution and never performs a hypothetical/guess branch.

const LEVEL_SIZES := {"easy": 6, "medium": 9, "hard": 12}


func valid_shape(puzzle: Dictionary) -> bool:
	var n := int(puzzle.get("size", 0))
	if not LEVEL_SIZES.values().has(n):
		return false
	var regions: Array = puzzle.get("regions", [])
	if regions.size() != n * n:
		return false
	var amounts := PackedInt32Array()
	amounts.resize(n)
	for value in regions:
		if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
			return false
		var region := int(value)
		if region < 0 or region >= n or float(value) != float(region):
			return false
		amounts[region] += 1
	for amount in amounts:
		if amount == 0:
			return false
	if not _regions_connected(n, regions):
		return false
	var givens: Array = puzzle.get("givens", [])
	if typeof(givens) != TYPE_ARRAY or givens.size() > 1:
		return false
	var used: Dictionary = {}
	for raw in givens:
		if typeof(raw) != TYPE_INT and typeof(raw) != TYPE_FLOAT:
			return false
		var cell := int(raw)
		if cell < 0 or cell >= n * n or float(raw) != float(cell) or used.has(cell):
			return false
		used[cell] = true
	return true


func _regions_connected(n: int, regions: Array) -> bool:
	for region in range(n):
		# JSON.parse_string decodes numeric IDs as floats. Array.find(int)
		# must not depend on float/int Variant equality.
		var start := -1
		for cell in range(n * n):
			if int(regions[cell]) == region:
				start = cell
				break
		if start == -1:
			return false
		var visited: Dictionary = {}
		visited[start] = true
		var pending := [start]
		while not pending.is_empty():
			var i: int = pending.pop_back()
			for j in _orthogonal(i, n):
				if int(regions[j]) == region and not visited.has(j):
					visited[j] = true
					pending.append(j)
		var count := 0
		for value in regions:
			if int(value) == region:
				count += 1
		if visited.size() != count:
			return false
	return true


func _orthogonal(i: int, n: int) -> Array:
	var y := i / n
	var x := i % n
	var neighbors: Array = []
	if x > 0: neighbors.append(i - 1)
	if x + 1 < n: neighbors.append(i + 1)
	if y > 0: neighbors.append(i - n)
	if y + 1 < n: neighbors.append(i + n)
	return neighbors


func count_solutions(puzzle: Dictionary, limit: int = 2) -> int:
	if not valid_shape(puzzle) or limit < 1:
		return 0
	return _count_solutions_unchecked(puzzle, limit)


func _count_solutions_unchecked(puzzle: Dictionary, limit: int = 2) -> int:
	## Row-by-row bounded DFS avoids materializing the 63+ million non-touching
	## permutations possible in a 12x12 puzzle. Stop at two solutions.
	var n := int(puzzle["size"])
	var pinned := PackedInt32Array()
	pinned.resize(n)
	pinned.fill(-1)
	for raw in puzzle.get("givens", []):
		var cell := int(raw)
		pinned[int(cell / n)] = cell % n
	return _count_search(n, puzzle["regions"], pinned, 0, 0, 0, -5, limit)


func _count_search(n: int, regions: Array, pinned: PackedInt32Array, row: int, columns: int, colors: int, last_col: int, remaining: int) -> int:
	if row == n:
		return 1
	var found := 0
	for col in range(n):
		if pinned[row] != -1 and pinned[row] != col:
			continue
		if (columns & (1 << col)) != 0 or (row > 0 and absi(col - last_col) <= 1):
			continue
		var region := int(regions[row * n + col])
		if (colors & (1 << region)) != 0:
			continue
		found += _count_search(n, regions, pinned, row + 1, columns | (1 << col), colors | (1 << region), col, remaining - found)
		if found >= remaining:
			return found
	return found


func solve_by_deduction(puzzle: Dictionary) -> Dictionary:
	## Deterministic rules: unit propagation (row, col, region), placed-cat
	## exclusions, and adjacent-row compatibility (arc consistency).
	## No trial placements, backtracking, uniqueness oracle, or answer lookup.
	if not valid_shape(puzzle):
		return {"solved": false, "passes": 0, "forced": []}
	var n := int(puzzle["size"])
	var regions: Array = puzzle["regions"]
	var candidates := PackedByteArray()
	candidates.resize(n * n)
	candidates.fill(1)
	var fixed: Dictionary = {}
	var trace: Array = []
	for raw in puzzle.get("givens", []):
		var given := int(raw)
		fixed[given] = true
		trace.append(given)
	var pass_count := 0
	var support_steps := 0
	while pass_count < 100:
		pass_count += 1
		var changed := false
		for raw in fixed.keys():
			var i := int(raw)
			var row := i / n
			var col := i % n
			for j in range(n * n):
				if i == j or candidates[j] == 0:
					continue
				var other_y := j / n
				var other_x := j % n
				if row == other_y or col == other_x or int(regions[i]) == int(regions[j]) or (absi(row - other_y) <= 1 and absi(col - other_x) <= 1):
					candidates[j] = 0
					changed = true
		for axis in range(3):
			for group_id in range(n):
				var options: Array = []
				for cell in range(n * n):
					if candidates[cell] == 0:
						continue
					if (axis == 0 and cell / n == group_id) or (axis == 1 and cell % n == group_id) or (axis == 2 and int(regions[cell]) == group_id):
						options.append(cell)
				if options.is_empty():
					return {"solved": false, "passes": pass_count, "forced": trace}
				if options.size() == 1 and not fixed.has(options[0]):
					fixed[options[0]] = true
					trace.append(options[0])
					changed = true
		for i in range(n * n):
			if candidates[i] == 0:
				continue
			var row := i / n
			var col := i % n
			for other_y in [row - 1, row + 1]:
				if other_y < 0 or other_y >= n:
					continue
				var supported := false
				for other_x in range(n):
					if candidates[other_y * n + other_x] != 0 and absi(col - other_x) > 1:
						supported = true
						break
				if not supported:
					candidates[i] = 0
					changed = true
					support_steps += 1
					break
		if fixed.size() == n:
			for i in fixed.keys():
				if candidates[int(i)] == 0:
					return {"solved": false, "passes": pass_count, "forced": trace}
			return {"solved": true, "passes": pass_count, "support_steps": support_steps, "forced": trace}
		if not changed:
			break
	return {"solved": false, "passes": pass_count, "support_steps": support_steps, "forced": trace}


func approved(puzzle: Dictionary) -> bool:
	if not valid_shape(puzzle):
		return false
	if count_solutions(puzzle) != 1:
		return false
	var deduction := solve_by_deduction(puzzle)
	return bool(deduction.get("solved", false))


func signature(puzzle: Dictionary) -> String:
	## Canonicalize colour IDs; arbitrary palette numbering isn't a new puzzle.
	var labels: Dictionary = {}
	var normalized := PackedStringArray()
	for value in puzzle.get("regions", []):
		var key := int(value)
		if not labels.has(key):
			labels[key] = labels.size()
		normalized.append(str(labels[key]))
	return "%s:%s" % [str(puzzle.get("size", 0)), ",".join(normalized)]


func is_win(puzzle: Dictionary, marks: PackedInt32Array) -> bool:
	if not valid_shape(puzzle):
		return false
	var n := int(puzzle["size"])
	if marks.size() != n * n:
		return false
	var cats: Array = []
	var row_used: Dictionary = {}
	var col_used: Dictionary = {}
	var region_used: Dictionary = {}
	for raw in puzzle.get("givens", []):
		if marks[int(raw)] != 1:
			return false
	for i in range(n * n):
		if marks[i] != 1:
			continue
		var row := i / n
		var col := i % n
		var region := int(puzzle["regions"][i])
		if row_used.has(row) or col_used.has(col) or region_used.has(region):
			return false
		row_used[row] = true
		col_used[col] = true
		region_used[region] = true
		for other in cats:
			if absi(row - (int(other) / n)) <= 1 and absi(col - (int(other) % n)) <= 1:
				return false
		cats.append(i)
	return cats.size() == n


func auto_exclusions(puzzle: Dictionary, marks: PackedInt32Array) -> PackedByteArray:
	var n := int(puzzle.get("size", 0))
	var excluded := PackedByteArray()
	excluded.resize(n * n)
	for i in range(mini(n * n, marks.size())):
		if marks[i] != 1:
			continue
		var row := i / n
		var col := i % n
		for j in range(n * n):
			if marks[j] != 0 or j == i:
				continue
			var other_y := j / n
			var other_x := j % n
			if row == other_y or col == other_x or int(puzzle["regions"][i]) == int(puzzle["regions"][j]) or (absi(row - other_y) <= 1 and absi(col - other_x) <= 1):
				excluded[j] = 1
	return excluded


func generate(level: String, rng: RandomNumberGenerator, max_attempts: int = 800) -> Dictionary:
	if not LEVEL_SIZES.has(level):
		return {}
	var n: int = LEVEL_SIZES[level]
	var small_count := 2 if level == "easy" else (6 if level == "medium" else 9)
	for attempt in range(max_attempts):
		var queens := _random_queens(n, rng)
		if queens.size() != n:
			continue
		var order: Array = []
		for row in range(n):
			order.append(row)
		for i in range(n - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var value = order[i]
			order[i] = order[j]
			order[j] = value
		var caps: Dictionary = {}
		for i in range(small_count):
			caps[int(order[i])] = 1 if rng.randi_range(0, 2) == 0 else 2
		var puzzle := _grow_regions(n, queens, caps, rng)
		if puzzle.is_empty():
			continue
		var sizes := PackedInt32Array()
		sizes.resize(n)
		for value in puzzle["regions"]:
			sizes[int(value)] += 1
		var too_large := false
		for count in sizes:
			if count > int(n * n / 2):
				too_large = true
				break
		if too_large:
			continue
		# Roughly one quarter of new puzzles begin with a visible fixed cat.
		var given_cells: Array = []
		if rng.randi_range(0, 3) == 0:
			var given_row := rng.randi_range(0, n - 1)
			given_cells.append(given_row * n + queens[given_row])
		puzzle["givens"] = given_cells
		if _count_solutions_unchecked(puzzle, 2) != 1:
			continue
		var proof := solve_by_deduction(puzzle)
		if not bool(proof.get("solved", false)):
			continue
		if level == "medium" and int(proof["passes"]) < 4:
			continue
		if level == "hard" and int(proof["passes"]) < (5 if not given_cells.is_empty() else 6):
			continue
		return puzzle
	return {}


func _random_queens(n: int, rng: RandomNumberGenerator) -> PackedInt32Array:
	var selected := PackedInt32Array()
	if _fill_random_queens(n, rng, selected, 0):
		return selected
	return PackedInt32Array()


func _fill_random_queens(n: int, rng: RandomNumberGenerator, selected: PackedInt32Array, used: int) -> bool:
	if selected.size() == n:
		return true
	var available: Array = []
	for col in range(n):
		available.append(col)
	for i in range(n - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var value = available[i]
		available[i] = available[j]
		available[j] = value
	for raw in available:
		var col := int(raw)
		if (used & (1 << col)) != 0:
			continue
		if not selected.is_empty() and absi(col - selected[selected.size() - 1]) <= 1:
			continue
		selected.append(col)
		if _fill_random_queens(n, rng, selected, used | (1 << col)):
			return true
		selected.remove_at(selected.size() - 1)
	return false


func _grow_regions(n: int, queens: PackedInt32Array, caps: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	## Grow an incremental random frontier instead of rescanning every empty
	## cell at each assignment. Bounded to O(board cells * neighbours) per try.
	var regions := PackedInt32Array()
	regions.resize(n * n)
	regions.fill(-1)
	var sizes := PackedInt32Array()
	sizes.resize(n)
	sizes.fill(1)
	var frontier: Array = []
	for row in range(n):
		regions[row * n + queens[row]] = row
	for row in range(n):
		for neighbor in _orthogonal(row * n + queens[row], n):
			if regions[neighbor] < 0:
				frontier.append([neighbor, row])
	var remaining := n * n - n
	while remaining > 0:
		if frontier.is_empty():
			return {}
		var edge: Array = frontier.pop_at(rng.randi_range(0, frontier.size() - 1))
		var target := int(edge[0])
		var region := int(edge[1])
		if regions[target] >= 0 or sizes[region] >= int(caps.get(region, n * n)):
			continue
		regions[target] = region
		sizes[region] += 1
		remaining -= 1
		for neighbor in _orthogonal(target, n):
			if regions[neighbor] < 0:
				frontier.append([neighbor, region])
	var board: Array = []
	for value in regions:
		board.append(value)
	return {"size": n, "regions": board}
