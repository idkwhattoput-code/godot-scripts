extends TileMap

export var auto_tile_on_ready: bool = true
export var update_neighbors: bool = true
export var tile_set_id: int = 0

var autotile_coords: Dictionary = {
	"top_left_corner": Vector2(0, 0),
	"top": Vector2(1, 0),
	"top_right_corner": Vector2(2, 0),
	"left": Vector2(0, 1),
	"center": Vector2(1, 1),
	"right": Vector2(2, 1),
	"bottom_left_corner": Vector2(0, 2),
	"bottom": Vector2(1, 2),
	"bottom_right_corner": Vector2(2, 2),
	"single": Vector2(3, 3)
}

var bitmask_values: Dictionary = {
	0: "single",
	2: "bottom",
	8: "right",
	10: "bottom_right_corner",
	11: "right",
	16: "top",
	18: "center",
	22: "right",
	24: "top_right_corner",
	26: "right",
	27: "right",
	30: "right",
	31: "right",
	64: "left",
	66: "bottom_left_corner",
	72: "center",
	74: "bottom",
	75: "bottom",
	80: "center",
	82: "center",
	86: "center",
	88: "top",
	90: "center",
	91: "right",
	94: "center",
	95: "right",
	104: "left",
	106: "bottom",
	107: "bottom",
	120: "top",
	122: "center",
	123: "right",
	126: "center",
	127: "right",
	208: "left",
	210: "left",
	214: "left",
	216: "left",
	218: "left",
	219: "left",
	222: "left",
	223: "left",
	248: "left",
	250: "left",
	251: "left",
	254: "left",
	255: "center"
}

signal autotile_completed()

func _ready() -> void:
	if auto_tile_on_ready:
		call_deferred("autotile_all")

func autotile_all() -> void:
	var used_cells = get_used_cells()
	for cell in used_cells:
		autotile_cell(cell.x, cell.y)
	
	emit_signal("autotile_completed")

func autotile_cell(x: int, y: int) -> void:
	if get_cell(x, y) == -1:
		return
	
	var bitmask = calculate_bitmask(x, y)
	var tile_type = get_tile_type_from_bitmask(bitmask)
	
	if autotile_coords.has(tile_type):
		set_cell(x, y, tile_set_id, false, false, false, autotile_coords[tile_type])
	
	if update_neighbors:
		update_neighbor_tiles(x, y)

func calculate_bitmask(x: int, y: int) -> int:
	var bitmask = 0
	
	if is_tile_at(x, y - 1): bitmask |= 16
	if is_tile_at(x + 1, y - 1): bitmask |= 32
	if is_tile_at(x + 1, y): bitmask |= 64
	if is_tile_at(x + 1, y + 1): bitmask |= 128
	if is_tile_at(x, y + 1): bitmask |= 1
	if is_tile_at(x - 1, y + 1): bitmask |= 2
	if is_tile_at(x - 1, y): bitmask |= 4
	if is_tile_at(x - 1, y - 1): bitmask |= 8
	
	return bitmask

func get_tile_type_from_bitmask(bitmask: int) -> String:
	if bitmask_values.has(bitmask):
		return bitmask_values[bitmask]
	
	var n = is_tile_at_bitmask(bitmask, 16)
	var e = is_tile_at_bitmask(bitmask, 64)
	var s = is_tile_at_bitmask(bitmask, 1)
	var w = is_tile_at_bitmask(bitmask, 4)
	
	if n and e and s and w:
		return "center"
	elif n and e and s:
		return "left"
	elif n and e and w:
		return "bottom"
	elif n and s and w:
		return "right"
	elif e and s and w:
		return "top"
	elif n and e:
		return "bottom_left_corner"
	elif n and w:
		return "bottom_right_corner"
	elif s and e:
		return "top_left_corner"
	elif s and w:
		return "top_right_corner"
	elif n and s:
		return "center"
	elif e and w:
		return "center"
	elif n:
		return "bottom"
	elif e:
		return "left"
	elif s:
		return "top"
	elif w:
		return "right"
	else:
		return "single"

func is_tile_at_bitmask(bitmask: int, value: int) -> bool:
	return (bitmask & value) == value

func is_tile_at(x: int, y: int) -> bool:
	return get_cell(x, y) != -1

func update_neighbor_tiles(x: int, y: int) -> void:
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			
			var nx = x + dx
			var ny = y + dy
			
			if is_tile_at(nx, ny):
				autotile_cell(nx, ny)

func set_cell_autotile(x: int, y: int, tile: int = tile_set_id) -> void:
	set_cell(x, y, tile)
	autotile_cell(x, y)

func remove_cell_autotile(x: int, y: int) -> void:
	set_cell(x, y, -1)
	update_neighbor_tiles(x, y)

func flood_fill(start_x: int, start_y: int, tile: int = tile_set_id) -> void:
	var stack = [Vector2(start_x, start_y)]
	var visited = {}
	
	while stack.size() > 0:
		var pos = stack.pop_back()
		var key = "%d,%d" % [pos.x, pos.y]
		
		if visited.has(key) or is_tile_at(pos.x, pos.y):
			continue
		
		visited[key] = true
		set_cell_autotile(pos.x, pos.y, tile)
		
		stack.push_back(Vector2(pos.x + 1, pos.y))
		stack.push_back(Vector2(pos.x - 1, pos.y))
		stack.push_back(Vector2(pos.x, pos.y + 1))
		stack.push_back(Vector2(pos.x, pos.y - 1))

func draw_line_tiles(start: Vector2, end: Vector2, tile: int = tile_set_id) -> void:
	var points = get_line_points(start, end)
	for point in points:
		set_cell_autotile(point.x, point.y, tile)

func get_line_points(start: Vector2, end: Vector2) -> Array:
	var points = []
	var x0 = int(start.x)
	var y0 = int(start.y)
	var x1 = int(end.x)
	var y1 = int(end.y)
	
	var dx = abs(x1 - x0)
	var dy = abs(y1 - y0)
	var sx = 1 if x0 < x1 else -1
	var sy = 1 if y0 < y1 else -1
	var err = dx - dy
	
	while true:
		points.append(Vector2(x0, y0))
		
		if x0 == x1 and y0 == y1:
			break
		
		var e2 = 2 * err
		if e2 > -dy:
			err -= dy
			x0 += sx
		if e2 < dx:
			err += dx
			y0 += sy
	
	return points

func draw_rect_tiles(start: Vector2, end: Vector2, tile: int = tile_set_id, filled: bool = true) -> void:
	var min_x = int(min(start.x, end.x))
	var max_x = int(max(start.x, end.x))
	var min_y = int(min(start.y, end.y))
	var max_y = int(max(start.y, end.y))
	
	if filled:
		for x in range(min_x, max_x + 1):
			for y in range(min_y, max_y + 1):
				set_cell_autotile(x, y, tile)
	else:
		for x in range(min_x, max_x + 1):
			set_cell_autotile(x, min_y, tile)
			set_cell_autotile(x, max_y, tile)
		
		for y in range(min_y + 1, max_y):
			set_cell_autotile(min_x, y, tile)
			set_cell_autotile(max_x, y, tile)