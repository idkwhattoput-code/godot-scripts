extends Node

class_name PuzzleSystem

signal puzzle_completed(puzzle_name)
signal puzzle_progress(puzzle_name, progress)
signal puzzle_failed(puzzle_name)
signal all_puzzles_solved()

export var puzzle_timeout: float = 120.0
export var allow_reset: bool = true
export var save_progress: bool = true

var active_puzzles: Dictionary = {}
var completed_puzzles: Array = []
var puzzle_save_data: Dictionary = {}

class PuzzleBase:
	var name: String = ""
	var description: String = ""
	var is_active: bool = false
	var is_completed: bool = false
	var progress: float = 0.0
	var time_started: float = 0.0
	var elements: Array = []
	var solution: Dictionary = {}
	var hints: Array = []
	var current_hint_index: int = 0
	
	func _init(puzzle_name: String, desc: String = ""):
		name = puzzle_name
		description = desc
	
	func start():
		is_active = true
		time_started = OS.get_ticks_msec() / 1000.0
		progress = 0.0
	
	func stop():
		is_active = false
	
	func reset():
		progress = 0.0
		is_completed = false
		is_active = false
		for element in elements:
			if element.has_method("reset"):
				element.reset()
	
	func check_solution() -> bool:
		return false
	
	func get_hint() -> String:
		if current_hint_index < hints.size():
			var hint = hints[current_hint_index]
			current_hint_index += 1
			return hint
		return "No more hints available"

class SequencePuzzle extends PuzzleBase:
	var sequence: Array = []
	var player_sequence: Array = []
	var max_sequence_length: int = 5
	
	func _init(name: String, length: int = 5).(name, "Complete the sequence in the correct order"):
		max_sequence_length = length
		generate_sequence()
	
	func generate_sequence():
		sequence.clear()
		for i in range(max_sequence_length):
			sequence.append(randi() % 4)
	
	func add_input(value: int):
		if not is_active:
			return
		
		player_sequence.append(value)
		progress = float(player_sequence.size()) / float(max_sequence_length)
		
		if player_sequence.size() > sequence.size():
			reset()
			return
		
		for i in range(player_sequence.size()):
			if player_sequence[i] != sequence[i]:
				reset()
				return
		
		if player_sequence.size() == sequence.size():
			is_completed = true
			stop()
	
	func check_solution() -> bool:
		return player_sequence == sequence

class PatternPuzzle extends PuzzleBase:
	var grid_size: Vector2 = Vector2(4, 4)
	var pattern: Array = []
	var player_pattern: Array = []
	var required_tiles: int = 0
	
	func _init(name: String, size: Vector2 = Vector2(4, 4)).(name, "Recreate the pattern"):
		grid_size = size
		generate_pattern()
	
	func generate_pattern():
		pattern.clear()
		player_pattern.clear()
		
		for y in range(grid_size.y):
			var row = []
			var player_row = []
			for x in range(grid_size.x):
				var is_active = randf() > 0.6
				row.append(is_active)
				player_row.append(false)
				if is_active:
					required_tiles += 1
			pattern.append(row)
			player_pattern.append(player_row)
	
	func toggle_tile(x: int, y: int):
		if not is_active or x >= grid_size.x or y >= grid_size.y:
			return
		
		player_pattern[y][x] = not player_pattern[y][x]
		update_progress()
	
	func update_progress():
		var correct_tiles = 0
		for y in range(grid_size.y):
			for x in range(grid_size.x):
				if player_pattern[y][x] == pattern[y][x]:
					correct_tiles += 1
		
		progress = float(correct_tiles) / float(grid_size.x * grid_size.y)
		
		if check_solution():
			is_completed = true
			stop()
	
	func check_solution() -> bool:
		for y in range(grid_size.y):
			for x in range(grid_size.x):
				if player_pattern[y][x] != pattern[y][x]:
					return false
		return true

class RotationPuzzle extends PuzzleBase:
	var pieces: Array = []
	var target_rotations: Array = []
	var current_rotations: Array = []
	var piece_count: int = 4
	
	func _init(name: String, pieces_num: int = 4).(name, "Rotate all pieces to correct orientation"):
		piece_count = pieces_num
		generate_puzzle()
	
	func generate_puzzle():
		pieces.clear()
		target_rotations.clear()
		current_rotations.clear()
		
		for i in range(piece_count):
			var target_rot = (randi() % 4) * 90
			target_rotations.append(target_rot)
			current_rotations.append(0)
	
	func rotate_piece(index: int, degrees: int = 90):
		if not is_active or index >= piece_count:
			return
		
		current_rotations[index] = int(current_rotations[index] + degrees) % 360
		update_progress()
	
	func update_progress():
		var correct_pieces = 0
		for i in range(piece_count):
			if current_rotations[i] == target_rotations[i]:
				correct_pieces += 1
		
		progress = float(correct_pieces) / float(piece_count)
		
		if check_solution():
			is_completed = true
			stop()
	
	func check_solution() -> bool:
		for i in range(piece_count):
			if current_rotations[i] != target_rotations[i]:
				return false
		return true

class SlidingPuzzle extends PuzzleBase:
	var grid_size: int = 4
	var tiles: Array = []
	var empty_pos: Vector2 = Vector2()
	var move_count: int = 0
	var optimal_moves: int = 0
	
	func _init(name: String, size: int = 4).(name, "Slide tiles to solve the puzzle"):
		grid_size = size
		generate_puzzle()
	
	func generate_puzzle():
		tiles.clear()
		var numbers = []
		
		for i in range(grid_size * grid_size - 1):
			numbers.append(i + 1)
		numbers.append(0)
		
		for y in range(grid_size):
			var row = []
			for x in range(grid_size):
				var index = y * grid_size + x
				row.append(numbers[index])
				if numbers[index] == 0:
					empty_pos = Vector2(x, y)
			tiles.append(row)
		
		shuffle_puzzle()
	
	func shuffle_puzzle():
		for i in range(100):
			var directions = [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]
			var dir = directions[randi() % 4]
			move_tile(empty_pos + dir)
		move_count = 0
	
	func move_tile(pos: Vector2):
		if not is_active:
			return
		
		if pos.x < 0 or pos.x >= grid_size or pos.y < 0 or pos.y >= grid_size:
			return
		
		var diff = (pos - empty_pos).abs()
		if diff.x + diff.y != 1:
			return
		
		tiles[empty_pos.y][empty_pos.x] = tiles[pos.y][pos.x]
		tiles[pos.y][pos.x] = 0
		empty_pos = pos
		move_count += 1
		
		update_progress()
	
	func update_progress():
		var correct_tiles = 0
		var total_tiles = grid_size * grid_size - 1
		
		for y in range(grid_size):
			for x in range(grid_size):
				if tiles[y][x] == 0:
					continue
				var expected = y * grid_size + x + 1
				if expected == grid_size * grid_size:
					expected = 0
				if tiles[y][x] == expected:
					correct_tiles += 1
		
		progress = float(correct_tiles) / float(total_tiles)
		
		if check_solution():
			is_completed = true
			stop()
	
	func check_solution() -> bool:
		for y in range(grid_size):
			for x in range(grid_size):
				var expected = y * grid_size + x + 1
				if expected == grid_size * grid_size:
					expected = 0
				if tiles[y][x] != expected:
					return false
		return true

class MemoryPuzzle extends PuzzleBase:
	var grid_size: Vector2 = Vector2(4, 4)
	var cards: Array = []
	var flipped_cards: Array = []
	var matched_pairs: int = 0
	var total_pairs: int = 0
	var flip_count: int = 0
	
	func _init(name: String, size: Vector2 = Vector2(4, 4)).(name, "Match all pairs"):
		grid_size = size
		total_pairs = int(size.x * size.y / 2)
		generate_puzzle()
	
	func generate_puzzle():
		cards.clear()
		var values = []
		
		for i in range(total_pairs):
			values.append(i)
			values.append(i)
		
		values.shuffle()
		
		for y in range(grid_size.y):
			var row = []
			for x in range(grid_size.x):
				var card = {
					"value": values[y * int(grid_size.x) + x],
					"is_flipped": false,
					"is_matched": false
				}
				row.append(card)
			cards.append(row)
	
	func flip_card(x: int, y: int):
		if not is_active or x >= grid_size.x or y >= grid_size.y:
			return
		
		var card = cards[y][x]
		if card.is_matched or card.is_flipped:
			return
		
		card.is_flipped = true
		flipped_cards.append(Vector2(x, y))
		flip_count += 1
		
		if flipped_cards.size() == 2:
			check_match()
	
	func check_match():
		var pos1 = flipped_cards[0]
		var pos2 = flipped_cards[1]
		var card1 = cards[pos1.y][pos1.x]
		var card2 = cards[pos2.y][pos2.x]
		
		if card1.value == card2.value:
			card1.is_matched = true
			card2.is_matched = true
			matched_pairs += 1
			progress = float(matched_pairs) / float(total_pairs)
			
			if matched_pairs == total_pairs:
				is_completed = true
				stop()
		else:
			yield(get_tree().create_timer(1.0), "timeout")
			card1.is_flipped = false
			card2.is_flipped = false
		
		flipped_cards.clear()

class ConnectionPuzzle extends PuzzleBase:
	var nodes: Array = []
	var connections: Array = []
	var required_connections: Array = []
	var node_count: int = 6
	
	func _init(name: String, nodes_num: int = 6).(name, "Connect all nodes correctly"):
		node_count = nodes_num
		generate_puzzle()
	
	func generate_puzzle():
		nodes.clear()
		connections.clear()
		required_connections.clear()
		
		for i in range(node_count):
			nodes.append({
				"id": i,
				"position": Vector2(randf() * 400, randf() * 400),
				"connected_to": []
			})
		
		for i in range(node_count - 1):
			var target = randi() % node_count
			while target == i:
				target = randi() % node_count
			required_connections.append([i, target])
	
	func connect_nodes(node1: int, node2: int):
		if not is_active or node1 >= node_count or node2 >= node_count:
			return
		
		if node1 == node2:
			return
		
		var connection = [min(node1, node2), max(node1, node2)]
		if not connection in connections:
			connections.append(connection)
			nodes[node1].connected_to.append(node2)
			nodes[node2].connected_to.append(node1)
		
		update_progress()
	
	func disconnect_nodes(node1: int, node2: int):
		if not is_active:
			return
		
		var connection = [min(node1, node2), max(node1, node2)]
		if connection in connections:
			connections.erase(connection)
			nodes[node1].connected_to.erase(node2)
			nodes[node2].connected_to.erase(node1)
		
		update_progress()
	
	func update_progress():
		var correct_connections = 0
		for req in required_connections:
			if req in connections or [req[1], req[0]] in connections:
				correct_connections += 1
		
		progress = float(correct_connections) / float(required_connections.size())
		
		if check_solution():
			is_completed = true
			stop()
	
	func check_solution() -> bool:
		for req in required_connections:
			if not (req in connections or [req[1], req[0]] in connections):
				return false
		return true

func _ready():
	if save_progress:
		load_puzzle_progress()

func create_puzzle(type: String, name: String, params: Dictionary = {}) -> PuzzleBase:
	var puzzle: PuzzleBase
	
	match type:
		"sequence":
			puzzle = SequencePuzzle.new(name, params.get("length", 5))
		"pattern":
			puzzle = PatternPuzzle.new(name, params.get("size", Vector2(4, 4)))
		"rotation":
			puzzle = RotationPuzzle.new(name, params.get("pieces", 4))
		"sliding":
			puzzle = SlidingPuzzle.new(name, params.get("grid_size", 4))
		"memory":
			puzzle = MemoryPuzzle.new(name, params.get("size", Vector2(4, 4)))
		"connection":
			puzzle = ConnectionPuzzle.new(name, params.get("nodes", 6))
		_:
			puzzle = PuzzleBase.new(name)
	
	active_puzzles[name] = puzzle
	return puzzle

func start_puzzle(puzzle_name: String):
	if puzzle_name in active_puzzles:
		var puzzle = active_puzzles[puzzle_name]
		puzzle.start()
		
		if puzzle_timeout > 0:
			var timer = Timer.new()
			timer.wait_time = puzzle_timeout
			timer.one_shot = true
			timer.connect("timeout", self, "_on_puzzle_timeout", [puzzle_name])
			add_child(timer)
			timer.start()

func stop_puzzle(puzzle_name: String):
	if puzzle_name in active_puzzles:
		active_puzzles[puzzle_name].stop()

func reset_puzzle(puzzle_name: String):
	if not allow_reset:
		return
	
	if puzzle_name in active_puzzles:
		active_puzzles[puzzle_name].reset()

func get_puzzle(puzzle_name: String) -> PuzzleBase:
	return active_puzzles.get(puzzle_name)

func get_puzzle_progress(puzzle_name: String) -> float:
	if puzzle_name in active_puzzles:
		return active_puzzles[puzzle_name].progress
	return 0.0

func is_puzzle_completed(puzzle_name: String) -> bool:
	if puzzle_name in active_puzzles:
		return active_puzzles[puzzle_name].is_completed
	return puzzle_name in completed_puzzles

func get_hint(puzzle_name: String) -> String:
	if puzzle_name in active_puzzles:
		return active_puzzles[puzzle_name].get_hint()
	return ""

func _on_puzzle_timeout(puzzle_name: String):
	if puzzle_name in active_puzzles:
		var puzzle = active_puzzles[puzzle_name]
		if puzzle.is_active and not puzzle.is_completed:
			puzzle.stop()
			emit_signal("puzzle_failed", puzzle_name)

func _process(delta):
	for puzzle_name in active_puzzles:
		var puzzle = active_puzzles[puzzle_name]
		if puzzle.is_active:
			emit_signal("puzzle_progress", puzzle_name, puzzle.progress)
			
			if puzzle.is_completed and not puzzle_name in completed_puzzles:
				completed_puzzles.append(puzzle_name)
				emit_signal("puzzle_completed", puzzle_name)
				
				if save_progress:
					save_puzzle_progress()
				
				check_all_puzzles_completed()

func check_all_puzzles_completed():
	var all_completed = true
	for puzzle_name in active_puzzles:
		if not active_puzzles[puzzle_name].is_completed:
			all_completed = false
			break
	
	if all_completed and active_puzzles.size() > 0:
		emit_signal("all_puzzles_solved")

func save_puzzle_progress():
	var save_file = File.new()
	save_file.open("user://puzzle_progress.save", File.WRITE)
	
	var save_data = {
		"completed_puzzles": completed_puzzles,
		"puzzle_states": {}
	}
	
	for puzzle_name in active_puzzles:
		var puzzle = active_puzzles[puzzle_name]
		save_data.puzzle_states[puzzle_name] = {
			"is_completed": puzzle.is_completed,
			"progress": puzzle.progress
		}
	
	save_file.store_string(to_json(save_data))
	save_file.close()

func load_puzzle_progress():
	var save_file = File.new()
	if not save_file.file_exists("user://puzzle_progress.save"):
		return
	
	save_file.open("user://puzzle_progress.save", File.READ)
	var save_data = parse_json(save_file.get_as_text())
	save_file.close()
	
	if save_data.has("completed_puzzles"):
		completed_puzzles = save_data.completed_puzzles
	
	puzzle_save_data = save_data.get("puzzle_states", {})

func clear_all_progress():
	completed_puzzles.clear()
	for puzzle_name in active_puzzles:
		active_puzzles[puzzle_name].reset()
	
	if save_progress:
		var dir = Directory.new()
		dir.remove("user://puzzle_progress.save")