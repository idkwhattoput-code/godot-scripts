extends Node

class_name DungeonGenerator

signal generation_started()
signal generation_progress(percent)
signal generation_completed(dungeon_data)
signal room_generated(room)
signal corridor_generated(corridor)

export var dungeon_size: Vector2 = Vector2(100, 100)
export var room_count: int = 20
export var min_room_size: Vector2 = Vector2(4, 4)
export var max_room_size: Vector2 = Vector2(12, 12)
export var corridor_width: int = 3
export var room_margin: int = 2
export var max_iterations: int = 1000
export var use_bsp: bool = false
export var bsp_depth: int = 4
export var connect_all_rooms: bool = true
export var add_loops: bool = true
export var loop_chance: float = 0.2

var grid: Array = []
var rooms: Array = []
var corridors: Array = []
var graph: Dictionary = {}
var start_room: Room = null
var end_room: Room = null
var special_rooms: Array = []

enum TileType {
	EMPTY,
	FLOOR,
	WALL,
	DOOR,
	CORRIDOR,
	ENTRANCE,
	EXIT,
	CHEST,
	TRAP,
	DECORATION
}

class Room:
	var position: Vector2
	var size: Vector2
	var center: Vector2
	var type: String = "normal"
	var connected_rooms: Array = []
	var tiles: Array = []
	var enemies: Array = []
	var items: Array = []
	var is_cleared: bool = false
	var room_id: int = 0
	
	func _init(pos: Vector2, s: Vector2):
		position = pos
		size = s
		center = position + size / 2
	
	func get_rect() -> Rect2:
		return Rect2(position, size)
	
	func overlaps(other: Room, margin: int = 0) -> bool:
		var expanded_rect = get_rect()
		expanded_rect = expanded_rect.grow(margin)
		return expanded_rect.intersects(other.get_rect())
	
	func distance_to(other: Room) -> float:
		return center.distance_to(other.center)

class Corridor:
	var start_pos: Vector2
	var end_pos: Vector2
	var path: Array = []
	var width: int = 3
	
	func _init(start: Vector2, end: Vector2, w: int = 3):
		start_pos = start
		end_pos = end
		width = w

class DungeonData:
	var grid_data: Array = []
	var rooms_data: Array = []
	var corridors_data: Array = []
	var start_position: Vector2
	var end_position: Vector2
	var special_positions: Dictionary = {}
	var total_size: Vector2

func _ready():
	randomize()

func generate_dungeon(config: Dictionary = {}) -> DungeonData:
	emit_signal("generation_started")
	
	if config.has("size"):
		dungeon_size = config.size
	if config.has("rooms"):
		room_count = config.rooms
	if config.has("min_room_size"):
		min_room_size = config.min_room_size
	if config.has("max_room_size"):
		max_room_size = config.max_room_size
	
	initialize_grid()
	
	if use_bsp:
		generate_bsp_rooms()
	else:
		generate_random_rooms()
	
	if rooms.size() < 2:
		push_error("Failed to generate enough rooms")
		return null
	
	emit_signal("generation_progress", 30)
	
	create_room_graph()
	generate_corridors()
	
	emit_signal("generation_progress", 60)
	
	assign_special_rooms()
	place_doors()
	add_room_features()
	
	emit_signal("generation_progress", 80)
	
	fill_walls()
	post_process_dungeon()
	
	emit_signal("generation_progress", 100)
	
	var dungeon_data = create_dungeon_data()
	emit_signal("generation_completed", dungeon_data)
	
	return dungeon_data

func initialize_grid():
	grid.clear()
	rooms.clear()
	corridors.clear()
	graph.clear()
	
	for y in range(dungeon_size.y):
		var row = []
		for x in range(dungeon_size.x):
			row.append(TileType.EMPTY)
		grid.append(row)

func generate_random_rooms():
	var iterations = 0
	
	while rooms.size() < room_count and iterations < max_iterations:
		iterations += 1
		
		var room_size = Vector2(
			randi() % int(max_room_size.x - min_room_size.x + 1) + min_room_size.x,
			randi() % int(max_room_size.y - min_room_size.y + 1) + min_room_size.y
		)
		
		var room_pos = Vector2(
			randi() % int(dungeon_size.x - room_size.x - 1) + 1,
			randi() % int(dungeon_size.y - room_size.y - 1) + 1
		)
		
		var new_room = Room.new(room_pos, room_size)
		new_room.room_id = rooms.size()
		
		var can_place = true
		for existing_room in rooms:
			if new_room.overlaps(existing_room, room_margin):
				can_place = false
				break
		
		if can_place:
			place_room(new_room)
			rooms.append(new_room)
			emit_signal("room_generated", new_room)

func generate_bsp_rooms():
	var root_node = BSPNode.new(Rect2(Vector2(1, 1), dungeon_size - Vector2(2, 2)))
	split_bsp_node(root_node, 0)
	create_rooms_from_bsp(root_node)

class BSPNode:
	var rect: Rect2
	var left_child: BSPNode = null
	var right_child: BSPNode = null
	var room: Room = null
	
	func _init(r: Rect2):
		rect = r

func split_bsp_node(node: BSPNode, depth: int):
	if depth >= bsp_depth:
		return
	
	var split_horizontal = randf() > 0.5
	
	if node.rect.size.x / node.rect.size.y > 1.5:
		split_horizontal = false
	elif node.rect.size.y / node.rect.size.x > 1.5:
		split_horizontal = true
	
	var max_size = int(node.rect.size.y if split_horizontal else node.rect.size.x)
	if max_size <= min_room_size.y * 2 if split_horizontal else min_room_size.x * 2:
		return
	
	var split = randi() % (max_size - int(min_room_size.y * 2 if split_horizontal else min_room_size.x * 2)) + int(min_room_size.y if split_horizontal else min_room_size.x)
	
	if split_horizontal:
		node.left_child = BSPNode.new(Rect2(node.rect.position, Vector2(node.rect.size.x, split)))
		node.right_child = BSPNode.new(Rect2(node.rect.position + Vector2(0, split), Vector2(node.rect.size.x, node.rect.size.y - split)))
	else:
		node.left_child = BSPNode.new(Rect2(node.rect.position, Vector2(split, node.rect.size.y)))
		node.right_child = BSPNode.new(Rect2(node.rect.position + Vector2(split, 0), Vector2(node.rect.size.x - split, node.rect.size.y)))
	
	split_bsp_node(node.left_child, depth + 1)
	split_bsp_node(node.right_child, depth + 1)

func create_rooms_from_bsp(node: BSPNode):
	if node.left_child != null or node.right_child != null:
		if node.left_child != null:
			create_rooms_from_bsp(node.left_child)
		if node.right_child != null:
			create_rooms_from_bsp(node.right_child)
		
		if node.left_child != null and node.right_child != null:
			connect_bsp_rooms(node.left_child, node.right_child)
	else:
		var room_size = Vector2(
			randi() % int(min(node.rect.size.x - 2, max_room_size.x) - min_room_size.x + 1) + min_room_size.x,
			randi() % int(min(node.rect.size.y - 2, max_room_size.y) - min_room_size.y + 1) + min_room_size.y
		)
		
		var room_pos = node.rect.position + Vector2(
			randi() % int(node.rect.size.x - room_size.x),
			randi() % int(node.rect.size.y - room_size.y)
		)
		
		var room = Room.new(room_pos, room_size)
		room.room_id = rooms.size()
		node.room = room
		place_room(room)
		rooms.append(room)
		emit_signal("room_generated", room)

func connect_bsp_rooms(left: BSPNode, right: BSPNode):
	var left_room = get_bsp_room(left)
	var right_room = get_bsp_room(right)
	
	if left_room != null and right_room != null:
		create_corridor(left_room.center, right_room.center)

func get_bsp_room(node: BSPNode) -> Room:
	if node.room != null:
		return node.room
	
	var left_room = null
	var right_room = null
	
	if node.left_child != null:
		left_room = get_bsp_room(node.left_child)
	if node.right_child != null:
		right_room = get_bsp_room(node.right_child)
	
	if left_room == null and right_room == null:
		return null
	elif left_room == null:
		return right_room
	elif right_room == null:
		return left_room
	else:
		return left_room if randf() > 0.5 else right_room

func place_room(room: Room):
	for y in range(room.size.y):
		for x in range(room.size.x):
			var grid_x = int(room.position.x + x)
			var grid_y = int(room.position.y + y)
			if is_valid_position(Vector2(grid_x, grid_y)):
				grid[grid_y][grid_x] = TileType.FLOOR
				room.tiles.append(Vector2(grid_x, grid_y))

func create_room_graph():
	graph.clear()
	
	for room in rooms:
		graph[room] = []
	
	if connect_all_rooms:
		create_minimum_spanning_tree()
	else:
		connect_nearest_rooms()
	
	if add_loops:
		add_extra_connections()

func create_minimum_spanning_tree():
	var connected_rooms = [rooms[0]]
	var unconnected_rooms = rooms.duplicate()
	unconnected_rooms.remove(0)
	
	while unconnected_rooms.size() > 0:
		var min_distance = INF
		var closest_pair = []
		
		for connected_room in connected_rooms:
			for unconnected_room in unconnected_rooms:
				var distance = connected_room.distance_to(unconnected_room)
				if distance < min_distance:
					min_distance = distance
					closest_pair = [connected_room, unconnected_room]
		
		if closest_pair.size() == 2:
			graph[closest_pair[0]].append(closest_pair[1])
			graph[closest_pair[1]].append(closest_pair[0])
			connected_rooms.append(closest_pair[1])
			unconnected_rooms.erase(closest_pair[1])

func connect_nearest_rooms():
	for room in rooms:
		var nearest_rooms = get_nearest_rooms(room, 3)
		for nearest in nearest_rooms:
			if not nearest in graph[room]:
				graph[room].append(nearest)
				graph[nearest].append(room)

func get_nearest_rooms(room: Room, count: int) -> Array:
	var distances = []
	
	for other_room in rooms:
		if other_room != room:
			distances.append({
				"room": other_room,
				"distance": room.distance_to(other_room)
			})
	
	distances.sort_custom(self, "sort_by_distance")
	
	var nearest = []
	for i in range(min(count, distances.size())):
		nearest.append(distances[i].room)
	
	return nearest

func sort_by_distance(a, b):
	return a.distance < b.distance

func add_extra_connections():
	for room in rooms:
		if randf() < loop_chance:
			var potential_connections = []
			for other_room in rooms:
				if other_room != room and not other_room in graph[room]:
					potential_connections.append(other_room)
			
			if potential_connections.size() > 0:
				var random_room = potential_connections[randi() % potential_connections.size()]
				graph[room].append(random_room)
				graph[random_room].append(room)

func generate_corridors():
	var connected_pairs = []
	
	for room in graph:
		for connected_room in graph[room]:
			var pair = [room, connected_room]
			pair.sort_custom(self, "sort_by_id")
			if not pair in connected_pairs:
				connected_pairs.append(pair)
				create_corridor(room.center, connected_room.center)

func sort_by_id(a, b):
	return a.room_id < b.room_id

func create_corridor(start: Vector2, end: Vector2):
	var corridor = Corridor.new(start, end, corridor_width)
	
	if randf() > 0.5:
		create_horizontal_corridor(int(start.x), int(end.x), int(start.y), corridor)
		create_vertical_corridor(int(start.y), int(end.y), int(end.x), corridor)
	else:
		create_vertical_corridor(int(start.y), int(end.y), int(start.x), corridor)
		create_horizontal_corridor(int(start.x), int(end.x), int(end.y), corridor)
	
	corridors.append(corridor)
	emit_signal("corridor_generated", corridor)

func create_horizontal_corridor(x1: int, x2: int, y: int, corridor: Corridor):
	var start_x = min(x1, x2)
	var end_x = max(x1, x2)
	
	for x in range(start_x, end_x + 1):
		for width in range(-corridor_width/2, corridor_width/2 + 1):
			var pos = Vector2(x, y + width)
			if is_valid_position(pos):
				if grid[pos.y][pos.x] == TileType.EMPTY:
					grid[pos.y][pos.x] = TileType.CORRIDOR
				corridor.path.append(pos)

func create_vertical_corridor(y1: int, y2: int, x: int, corridor: Corridor):
	var start_y = min(y1, y2)
	var end_y = max(y1, y2)
	
	for y in range(start_y, end_y + 1):
		for width in range(-corridor_width/2, corridor_width/2 + 1):
			var pos = Vector2(x + width, y)
			if is_valid_position(pos):
				if grid[pos.y][pos.x] == TileType.EMPTY:
					grid[pos.y][pos.x] = TileType.CORRIDOR
				corridor.path.append(pos)

func assign_special_rooms():
	if rooms.size() < 2:
		return
	
	rooms.sort_custom(self, "sort_by_distance_from_center")
	
	start_room = rooms[0]
	start_room.type = "entrance"
	place_special_tile(start_room.center, TileType.ENTRANCE)
	
	end_room = rooms[rooms.size() - 1]
	end_room.type = "exit"
	place_special_tile(end_room.center, TileType.EXIT)
	
	if rooms.size() > 4:
		var treasure_room = rooms[randi() % (rooms.size() - 2) + 1]
		treasure_room.type = "treasure"
		special_rooms.append(treasure_room)
		
		var boss_room = rooms[rooms.size() - 2]
		boss_room.type = "boss"
		special_rooms.append(boss_room)

func sort_by_distance_from_center(a, b):
	var center = dungeon_size / 2
	return a.center.distance_to(center) < b.center.distance_to(center)

func place_doors():
	for room in rooms:
		var door_positions = []
		
		for y in range(room.size.y):
			for x in range(room.size.x):
				var pos = room.position + Vector2(x, y)
				
				if (x == 0 or x == room.size.x - 1 or y == 0 or y == room.size.y - 1):
					var adjacent_pos = []
					
					if x == 0:
						adjacent_pos.append(pos + Vector2.LEFT)
					elif x == room.size.x - 1:
						adjacent_pos.append(pos + Vector2.RIGHT)
					if y == 0:
						adjacent_pos.append(pos + Vector2.UP)
					elif y == room.size.y - 1:
						adjacent_pos.append(pos + Vector2.DOWN)
					
					for adj_pos in adjacent_pos:
						if is_valid_position(adj_pos) and grid[adj_pos.y][adj_pos.x] == TileType.CORRIDOR:
							door_positions.append(pos)
							break
		
		for door_pos in door_positions:
			grid[door_pos.y][door_pos.x] = TileType.DOOR

func add_room_features():
	for room in rooms:
		match room.type:
			"treasure":
				add_treasure_chests(room)
			"boss":
				add_boss_features(room)
			"normal":
				if randf() < 0.3:
					add_traps(room)
				if randf() < 0.5:
					add_decorations(room)

func add_treasure_chests(room: Room):
	var chest_count = randi() % 3 + 1
	for i in range(chest_count):
		var pos = get_random_floor_position(room)
		if pos != Vector2.ZERO:
			place_special_tile(pos, TileType.CHEST)

func add_boss_features(room: Room):
	var center = room.position + room.size / 2
	for y in range(-1, 2):
		for x in range(-1, 2):
			var pos = center + Vector2(x, y)
			if is_valid_position(pos) and grid[pos.y][pos.x] == TileType.FLOOR:
				place_special_tile(pos, TileType.DECORATION)

func add_traps(room: Room):
	var trap_count = randi() % 4 + 1
	for i in range(trap_count):
		var pos = get_random_floor_position(room)
		if pos != Vector2.ZERO:
			place_special_tile(pos, TileType.TRAP)

func add_decorations(room: Room):
	var decoration_count = randi() % 6 + 2
	for i in range(decoration_count):
		var pos = get_random_floor_position(room)
		if pos != Vector2.ZERO:
			place_special_tile(pos, TileType.DECORATION)

func get_random_floor_position(room: Room) -> Vector2:
	var attempts = 0
	while attempts < 50:
		var x = randi() % int(room.size.x - 2) + 1
		var y = randi() % int(room.size.y - 2) + 1
		var pos = room.position + Vector2(x, y)
		
		if is_valid_position(pos) and grid[pos.y][pos.x] == TileType.FLOOR:
			return pos
		attempts += 1
	
	return Vector2.ZERO

func place_special_tile(pos: Vector2, tile_type: int):
	if is_valid_position(pos):
		grid[int(pos.y)][int(pos.x)] = tile_type

func fill_walls():
	for y in range(dungeon_size.y):
		for x in range(dungeon_size.x):
			if grid[y][x] == TileType.EMPTY:
				var has_adjacent_floor = false
				
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						if dx == 0 and dy == 0:
							continue
						
						var check_pos = Vector2(x + dx, y + dy)
						if is_valid_position(check_pos):
							var tile = grid[check_pos.y][check_pos.x]
							if tile == TileType.FLOOR or tile == TileType.CORRIDOR or tile == TileType.DOOR:
								has_adjacent_floor = true
								break
					
					if has_adjacent_floor:
						break
				
				if has_adjacent_floor:
					grid[y][x] = TileType.WALL

func post_process_dungeon():
	remove_isolated_walls()
	smooth_walls()
	ensure_connectivity()

func remove_isolated_walls():
	for y in range(1, dungeon_size.y - 1):
		for x in range(1, dungeon_size.x - 1):
			if grid[y][x] == TileType.WALL:
				var wall_count = 0
				
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						if grid[y + dy][x + dx] == TileType.WALL:
							wall_count += 1
				
				if wall_count <= 2:
					grid[y][x] = TileType.EMPTY

func smooth_walls():
	var new_grid = grid.duplicate(true)
	
	for y in range(1, dungeon_size.y - 1):
		for x in range(1, dungeon_size.x - 1):
			if grid[y][x] == TileType.WALL:
				var floor_neighbors = 0
				
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						if dy == 0 and dx == 0:
							continue
						
						var tile = grid[y + dy][x + dx]
						if tile == TileType.FLOOR or tile == TileType.CORRIDOR:
							floor_neighbors += 1
				
				if floor_neighbors >= 5:
					new_grid[y][x] = TileType.FLOOR
	
	grid = new_grid

func ensure_connectivity():
	var visited = {}
	var start_pos = start_room.center
	
	flood_fill(int(start_pos.x), int(start_pos.y), visited)
	
	var all_connected = true
	for room in rooms:
		var room_connected = false
		for tile_pos in room.tiles:
			if tile_pos in visited:
				room_connected = true
				break
		
		if not room_connected:
			all_connected = false
			connect_room_to_nearest_connected(room, visited)

func flood_fill(x: int, y: int, visited: Dictionary):
	var stack = [[x, y]]
	
	while stack.size() > 0:
		var pos = stack.pop_back()
		var px = pos[0]
		var py = pos[1]
		
		if not is_valid_position(Vector2(px, py)):
			continue
		
		var key = Vector2(px, py)
		if key in visited:
			continue
		
		var tile = grid[py][px]
		if tile == TileType.WALL or tile == TileType.EMPTY:
			continue
		
		visited[key] = true
		
		stack.append([px + 1, py])
		stack.append([px - 1, py])
		stack.append([px, py + 1])
		stack.append([px, py - 1])

func connect_room_to_nearest_connected(room: Room, visited: Dictionary):
	var min_distance = INF
	var nearest_connected_pos = Vector2.ZERO
	
	for pos in visited:
		var distance = room.center.distance_to(pos)
		if distance < min_distance:
			min_distance = distance
			nearest_connected_pos = pos
	
	if nearest_connected_pos != Vector2.ZERO:
		create_corridor(room.center, nearest_connected_pos)

func is_valid_position(pos: Vector2) -> bool:
	return pos.x >= 0 and pos.x < dungeon_size.x and pos.y >= 0 and pos.y < dungeon_size.y

func create_dungeon_data() -> DungeonData:
	var data = DungeonData.new()
	data.grid_data = grid
	data.rooms_data = rooms
	data.corridors_data = corridors
	data.start_position = start_room.center if start_room else Vector2.ZERO
	data.end_position = end_room.center if end_room else Vector2.ZERO
	data.total_size = dungeon_size
	
	for room in special_rooms:
		data.special_positions[room.type] = room.center
	
	return data

func get_tile_at(pos: Vector2) -> int:
	if is_valid_position(pos):
		return grid[int(pos.y)][int(pos.x)]
	return TileType.EMPTY

func get_room_at(pos: Vector2) -> Room:
	for room in rooms:
		if room.get_rect().has_point(pos):
			return room
	return null

func get_path_between_rooms(start_room: Room, end_room: Room) -> Array:
	if not start_room in graph or not end_room in graph:
		return []
	
	var visited = {}
	var queue = [[start_room]]
	
	while queue.size() > 0:
		var path = queue.pop_front()
		var current_room = path[path.size() - 1]
		
		if current_room == end_room:
			return path
		
		if current_room in visited:
			continue
		
		visited[current_room] = true
		
		for connected_room in graph[current_room]:
			if not connected_room in visited:
				var new_path = path.duplicate()
				new_path.append(connected_room)
				queue.append(new_path)
	
	return []