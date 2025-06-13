extends Node3D

class_name SlidingPuzzle

@export var grid_size := Vector2i(4, 4)
@export var tile_size := 1.0
@export var slide_speed := 5.0
@export var tile_scene: PackedScene
@export var on_solved_signal_name := "puzzle_solved"

var tiles := []
var empty_position := Vector2i()
var is_sliding := false
var move_queue := []
var is_solved := false

signal puzzle_solved()
signal tile_moved(from: Vector2i, to: Vector2i)

func _ready():
	initialize_puzzle()
	shuffle_puzzle()

func initialize_puzzle():
	tiles.clear()
	
	for y in range(grid_size.y):
		var row := []
		for x in range(grid_size.x):
			if x == grid_size.x - 1 and y == grid_size.y - 1:
				row.append(null)
				empty_position = Vector2i(x, y)
			else:
				var tile = create_tile(x, y)
				row.append(tile)
		tiles.append(row)

func create_tile(x: int, y: int) -> Node3D:
	var tile = tile_scene.instantiate() if tile_scene else CSGBox3D.new()
	add_child(tile)
	
	if tile is CSGBox3D:
		tile.size = Vector3(tile_size * 0.9, 0.2, tile_size * 0.9)
	
	tile.position = grid_to_world(Vector2i(x, y))
	tile.set_meta("correct_position", Vector2i(x, y))
	tile.set_meta("current_position", Vector2i(x, y))
	
	if tile.has_method("set_number"):
		tile.set_number(y * grid_size.x + x + 1)
	
	var area = Area3D.new()
	var collision = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = Vector3(tile_size * 0.9, 0.2, tile_size * 0.9)
	collision.shape = shape
	area.add_child(collision)
	tile.add_child(area)
	
	area.input_event.connect(_on_tile_clicked.bind(tile))
	area.mouse_entered.connect(_on_tile_hover_start.bind(tile))
	area.mouse_exited.connect(_on_tile_hover_end.bind(tile))
	
	return tile

func grid_to_world(grid_pos: Vector2i) -> Vector3:
	return Vector3(
		(grid_pos.x - grid_size.x / 2.0 + 0.5) * tile_size,
		0,
		(grid_pos.y - grid_size.y / 2.0 + 0.5) * tile_size
	)

func world_to_grid(world_pos: Vector3) -> Vector2i:
	return Vector2i(
		int(round((world_pos.x / tile_size) + grid_size.x / 2.0 - 0.5)),
		int(round((world_pos.z / tile_size) + grid_size.y / 2.0 - 0.5))
	)

func shuffle_puzzle():
	var moves := grid_size.x * grid_size.y * 100
	for i in range(moves):
		var possible_moves := get_possible_moves()
		if possible_moves.size() > 0:
			var random_move = possible_moves[randi() % possible_moves.size()]
			swap_tiles(random_move, empty_position, true)

func get_possible_moves() -> Array[Vector2i]:
	var moves: Array[Vector2i] = []
	var directions = [
		Vector2i(0, -1),
		Vector2i(1, 0),
		Vector2i(0, 1),
		Vector2i(-1, 0)
	]
	
	for dir in directions:
		var new_pos = empty_position + dir
		if is_valid_position(new_pos):
			moves.append(new_pos)
	
	return moves

func is_valid_position(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.x < grid_size.x and pos.y >= 0 and pos.y < grid_size.y

func _on_tile_clicked(camera: Node, event: InputEvent, position: Vector3, normal: Vector3, shape_idx: int, tile: Node3D):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if not is_sliding and not is_solved:
			var tile_pos = tile.get_meta("current_position")
			try_move_tile(tile_pos)

func try_move_tile(tile_pos: Vector2i):
	if is_adjacent_to_empty(tile_pos):
		move_queue.append({"from": tile_pos, "to": empty_position})
		if not is_sliding:
			process_move_queue()

func is_adjacent_to_empty(tile_pos: Vector2i) -> bool:
	var diff = tile_pos - empty_position
	return abs(diff.x) + abs(diff.y) == 1

func process_move_queue():
	if move_queue.size() == 0:
		is_sliding = false
		check_win_condition()
		return
	
	is_sliding = true
	var move = move_queue.pop_front()
	animate_tile_slide(move.from, move.to)

func animate_tile_slide(from: Vector2i, to: Vector2i):
	var tile = tiles[from.y][from.x]
	if not tile:
		process_move_queue()
		return
	
	var start_pos = tile.position
	var end_pos = grid_to_world(to)
	
	var tween = create_tween()
	tween.tween_property(tile, "position", end_pos, 1.0 / slide_speed)
	tween.finished.connect(_on_slide_complete.bind(from, to))

func _on_slide_complete(from: Vector2i, to: Vector2i):
	swap_tiles(from, to, false)
	emit_signal("tile_moved", from, to)
	process_move_queue()

func swap_tiles(pos1: Vector2i, pos2: Vector2i, instant: bool = false):
	var tile1 = tiles[pos1.y][pos1.x]
	var tile2 = tiles[pos2.y][pos2.x]
	
	tiles[pos1.y][pos1.x] = tile2
	tiles[pos2.y][pos2.x] = tile1
	
	if tile1:
		tile1.set_meta("current_position", pos2)
		if instant:
			tile1.position = grid_to_world(pos2)
	
	if tile2:
		tile2.set_meta("current_position", pos1)
		if instant:
			tile2.position = grid_to_world(pos1)
	
	if not tile1:
		empty_position = pos2
	elif not tile2:
		empty_position = pos1

func check_win_condition():
	for y in range(grid_size.y):
		for x in range(grid_size.x):
			var tile = tiles[y][x]
			if tile:
				var correct_pos = tile.get_meta("correct_position")
				var current_pos = tile.get_meta("current_position")
				if correct_pos != current_pos:
					return
			elif x != grid_size.x - 1 or y != grid_size.y - 1:
				return
	
	is_solved = true
	emit_signal("puzzle_solved")
	if has_signal(on_solved_signal_name):
		emit_signal(on_solved_signal_name)

func _on_tile_hover_start(tile: Node3D):
	if tile.has_method("highlight"):
		tile.highlight(true)

func _on_tile_hover_end(tile: Node3D):
	if tile.has_method("highlight"):
		tile.highlight(false)

func reset_puzzle():
	is_solved = false
	is_sliding = false
	move_queue.clear()
	
	for y in range(grid_size.y):
		for x in range(grid_size.x):
			var tile = tiles[y][x]
			if tile:
				var correct_pos = tile.get_meta("correct_position")
				tile.position = grid_to_world(correct_pos)
				tile.set_meta("current_position", correct_pos)
				tiles[correct_pos.y][correct_pos.x] = tile
	
	empty_position = Vector2i(grid_size.x - 1, grid_size.y - 1)
	tiles[empty_position.y][empty_position.x] = null
	
	shuffle_puzzle()

func get_completion_percentage() -> float:
	var correct_tiles := 0
	var total_tiles := grid_size.x * grid_size.y - 1
	
	for y in range(grid_size.y):
		for x in range(grid_size.x):
			var tile = tiles[y][x]
			if tile:
				var correct_pos = tile.get_meta("correct_position")
				var current_pos = tile.get_meta("current_position")
				if correct_pos == current_pos:
					correct_tiles += 1
	
	return float(correct_tiles) / float(total_tiles) * 100.0