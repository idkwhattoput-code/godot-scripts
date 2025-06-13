extends Node2D

class_name DungeonGenerator2D

@export_group("Dungeon Settings")
@export var dungeon_width := 50
@export var dungeon_height := 50
@export var room_count := 10
@export var min_room_size := 4
@export var max_room_size := 10
@export var corridor_width := 3
@export var room_padding := 2

@export_group("Generation Settings")
@export var seed_value := 0
@export var use_random_seed := true
@export var connect_all_rooms := true
@export var add_loops := true
@export var loop_chance := 0.2

@export_group("Tiles")
@export var tilemap_path: NodePath
@export var wall_tile_id := 0
@export var floor_tile_id := 1
@export var door_tile_id := 2
@export var corridor_tile_id := 3

@export_group("Special Rooms")
@export var create_spawn_room := true
@export var create_boss_room := true
@export var create_treasure_rooms := true
@export var treasure_room_count := 3

@export_group("Decorations")
@export var add_torches := true
@export var torch_spacing := 5
@export var add_props := true
@export var prop_scenes: Array[PackedScene] = []

var tilemap: TileMap
var dungeon_data := {}
var rooms := []
var corridors := []
var spawn_point := Vector2.ZERO
var boss_room_center := Vector2.ZERO
var treasure_rooms := []
var graph := {}
var rng := RandomNumberGenerator.new()

signal generation_started()
signal generation_completed()
signal room_created(room: Rect2)
signal corridor_created(start: Vector2, end: Vector2)

class Room:
	var rect: Rect2
	var connections := []
	var room_type := "normal"
	var id := 0
	
	func _init(x: float, y: float, width: float, height: float):
		rect = Rect2(x, y, width, height)
	
	func get_center() -> Vector2:
		return rect.get_center()
	
	func distance_to(other_room: Room) -> float:
		return get_center().distance_to(other_room.get_center())

func _ready():
	if tilemap_path:
		tilemap = get_node(tilemap_path)
	
	if not tilemap:
		push_error("DungeonGenerator2D: No tilemap assigned!")
		return
	
	if use_random_seed:
		seed_value = randi()
	
	rng.seed = seed_value

func generate_dungeon():
	emit_signal("generation_started")
	
	clear_dungeon()
	
	generate_rooms()
	
	if connect_all_rooms:
		connect_rooms_mst()
	else:
		connect_rooms_nearest()
	
	if add_loops:
		add_corridor_loops()
	
	carve_dungeon()
	
	assign_special_rooms()
	
	if add_torches:
		place_torches()
	
	if add_props:
		place_props()
	
	emit_signal("generation_completed")

func clear_dungeon():
	dungeon_data.clear()
	rooms.clear()
	corridors.clear()
	treasure_rooms.clear()
	graph.clear()
	
	if tilemap:
		tilemap.clear()
	
	for y in range(dungeon_height):
		for x in range(dungeon_width):
			dungeon_data[Vector2(x, y)] = "wall"

func generate_rooms():
	var attempts := 0
	var max_attempts := 1000
	
	while rooms.size() < room_count and attempts < max_attempts:
		attempts += 1
		
		var room_width = rng.randi_range(min_room_size, max_room_size)
		var room_height = rng.randi_range(min_room_size, max_room_size)
		var x = rng.randi_range(1, dungeon_width - room_width - 1)
		var y = rng.randi_range(1, dungeon_height - room_height - 1)
		
		var new_room = Room.new(x, y, room_width, room_height)
		new_room.id = rooms.size()
		
		if not room_overlaps(new_room):
			rooms.append(new_room)
			emit_signal("room_created", new_room.rect)

func room_overlaps(room: Room) -> bool:
	for existing_room in rooms:
		var expanded_rect = existing_room.rect.grow(room_padding)
		if expanded_rect.intersects(room.rect):
			return true
	return false

func connect_rooms_mst():
	if rooms.size() < 2:
		return
	
	var edges := []
	for i in range(rooms.size()):
		for j in range(i + 1, rooms.size()):
			var distance = rooms[i].distance_to(rooms[j])
			edges.append({
				"from": i,
				"to": j,
				"distance": distance
			})
	
	edges.sort_custom(func(a, b): return a.distance < b.distance)
	
	var parent := {}
	for i in range(rooms.size()):
		parent[i] = i
	
	var find_parent = func(node: int) -> int:
		while parent[node] != node:
			node = parent[node]
		return node
	
	for edge in edges:
		var parent_from = find_parent.call(edge.from)
		var parent_to = find_parent.call(edge.to)
		
		if parent_from != parent_to:
			parent[parent_from] = parent_to
			create_corridor(rooms[edge.from], rooms[edge.to])
			
			rooms[edge.from].connections.append(edge.to)
			rooms[edge.to].connections.append(edge.from)

func connect_rooms_nearest():
	for i in range(rooms.size() - 1):
		var nearest_index = i + 1
		var nearest_distance = rooms[i].distance_to(rooms[i + 1])
		
		for j in range(i + 1, rooms.size()):
			var distance = rooms[i].distance_to(rooms[j])
			if distance < nearest_distance:
				nearest_distance = distance
				nearest_index = j
		
		create_corridor(rooms[i], rooms[nearest_index])
		rooms[i].connections.append(nearest_index)
		rooms[nearest_index].connections.append(i)

func add_corridor_loops():
	for i in range(rooms.size()):
		if rng.randf() < loop_chance:
			var potential_connections := []
			
			for j in range(rooms.size()):
				if i != j and not j in rooms[i].connections:
					potential_connections.append(j)
			
			if potential_connections.size() > 0:
				var target = potential_connections[rng.randi() % potential_connections.size()]
				create_corridor(rooms[i], rooms[target])
				rooms[i].connections.append(target)
				rooms[target].connections.append(i)

func create_corridor(room1: Room, room2: Room):
	var start = room1.get_center()
	var end = room2.get_center()
	
	var corridor_path := []
	
	if rng.randf() < 0.5:
		corridor_path = create_l_shaped_corridor(start, end, true)
	else:
		corridor_path = create_l_shaped_corridor(start, end, false)
	
	corridors.append(corridor_path)
	emit_signal("corridor_created", start, end)

func create_l_shaped_corridor(start: Vector2, end: Vector2, horizontal_first: bool) -> Array:
	var path := []
	
	if horizontal_first:
		for x in range(min(start.x, end.x), max(start.x, end.x) + 1):
			path.append(Vector2(x, start.y))
		for y in range(min(start.y, end.y), max(start.y, end.y) + 1):
			path.append(Vector2(end.x, y))
	else:
		for y in range(min(start.y, end.y), max(start.y, end.y) + 1):
			path.append(Vector2(start.x, y))
		for x in range(min(start.x, end.x), max(start.x, end.x) + 1):
			path.append(Vector2(x, end.y))
	
	return path

func carve_dungeon():
	for room in rooms:
		for y in range(room.rect.position.y, room.rect.position.y + room.rect.size.y):
			for x in range(room.rect.position.x, room.rect.position.x + room.rect.size.x):
				dungeon_data[Vector2(x, y)] = "floor"
	
	for corridor in corridors:
		for pos in corridor:
			for dy in range(-corridor_width/2, corridor_width/2 + 1):
				for dx in range(-corridor_width/2, corridor_width/2 + 1):
					var corridor_pos = pos + Vector2(dx, dy)
					if corridor_pos.x >= 0 and corridor_pos.x < dungeon_width and \
					   corridor_pos.y >= 0 and corridor_pos.y < dungeon_height:
						dungeon_data[corridor_pos] = "corridor"
	
	for y in range(dungeon_height):
		for x in range(dungeon_width):
			var pos = Vector2(x, y)
			var tile_type = dungeon_data.get(pos, "wall")
			
			match tile_type:
				"wall":
					tilemap.set_cell(0, Vector2i(x, y), wall_tile_id, Vector2i(0, 0))
				"floor":
					tilemap.set_cell(0, Vector2i(x, y), floor_tile_id, Vector2i(0, 0))
				"corridor":
					tilemap.set_cell(0, Vector2i(x, y), corridor_tile_id, Vector2i(0, 0))
				"door":
					tilemap.set_cell(0, Vector2i(x, y), door_tile_id, Vector2i(0, 0))

func assign_special_rooms():
	if rooms.size() == 0:
		return
	
	if create_spawn_room:
		rooms[0].room_type = "spawn"
		spawn_point = rooms[0].get_center() * tilemap.tile_set.tile_size
	
	if create_boss_room and rooms.size() > 1:
		var farthest_room = rooms[1]
		var max_distance = rooms[0].distance_to(rooms[1])
		
		for i in range(2, rooms.size()):
			var distance = rooms[0].distance_to(rooms[i])
			if distance > max_distance:
				max_distance = distance
				farthest_room = rooms[i]
		
		farthest_room.room_type = "boss"
		boss_room_center = farthest_room.get_center() * tilemap.tile_set.tile_size
	
	if create_treasure_rooms:
		var available_rooms := []
		for room in rooms:
			if room.room_type == "normal":
				available_rooms.append(room)
		
		for i in range(min(treasure_room_count, available_rooms.size())):
			var index = rng.randi() % available_rooms.size()
			available_rooms[index].room_type = "treasure"
			treasure_rooms.append(available_rooms[index])
			available_rooms.remove_at(index)

func place_torches():
	for room in rooms:
		var torch_positions := []
		
		for x in range(room.rect.position.x + 1, room.rect.position.x + room.rect.size.x - 1, torch_spacing):
			torch_positions.append(Vector2(x, room.rect.position.y))
			torch_positions.append(Vector2(x, room.rect.position.y + room.rect.size.y - 1))
		
		for y in range(room.rect.position.y + 1, room.rect.position.y + room.rect.size.y - 1, torch_spacing):
			torch_positions.append(Vector2(room.rect.position.x, y))
			torch_positions.append(Vector2(room.rect.position.x + room.rect.size.x - 1, y))
		
		for pos in torch_positions:
			if is_wall_adjacent(pos):
				create_torch(pos)

func is_wall_adjacent(pos: Vector2) -> bool:
	var directions = [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]
	for dir in directions:
		var check_pos = pos + dir
		if dungeon_data.get(check_pos, "wall") == "wall":
			return true
	return false

func create_torch(pos: Vector2):
	var torch = Node2D.new()
	torch.name = "Torch"
	torch.position = pos * tilemap.tile_set.tile_size
	
	var light = PointLight2D.new()
	light.energy = 0.8
	light.texture_scale = 2.0
	light.color = Color(1.0, 0.8, 0.4)
	torch.add_child(light)
	
	add_child(torch)

func place_props():
	if prop_scenes.size() == 0:
		return
	
	for room in rooms:
		if room.room_type == "normal" or room.room_type == "treasure":
			var prop_count = rng.randi_range(0, 3)
			
			for i in range(prop_count):
				var attempts = 0
				while attempts < 10:
					var x = rng.randi_range(room.rect.position.x + 1, room.rect.position.x + room.rect.size.x - 2)
					var y = rng.randi_range(room.rect.position.y + 1, room.rect.position.y + room.rect.size.y - 2)
					var pos = Vector2(x, y)
					
					if dungeon_data.get(pos, "wall") == "floor":
						var prop_scene = prop_scenes[rng.randi() % prop_scenes.size()]
						var prop = prop_scene.instantiate()
						prop.position = pos * tilemap.tile_set.tile_size
						add_child(prop)
						break
					
					attempts += 1

func get_spawn_point() -> Vector2:
	return spawn_point

func get_boss_room_center() -> Vector2:
	return boss_room_center

func get_room_at_position(pos: Vector2) -> Room:
	for room in rooms:
		if room.rect.has_point(pos / tilemap.tile_set.tile_size):
			return room
	return null

func is_position_walkable(pos: Vector2) -> bool:
	var tile_pos = pos / tilemap.tile_set.tile_size
	return dungeon_data.get(tile_pos, "wall") != "wall"