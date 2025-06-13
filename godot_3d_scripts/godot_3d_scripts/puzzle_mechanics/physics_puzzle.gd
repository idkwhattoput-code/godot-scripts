extends Node3D

signal puzzle_solved
signal puzzle_reset
signal piece_moved(piece_name: String, position: Vector3)

@export var puzzle_pieces: Array[RigidBody3D] = []
@export var target_positions: Array[Vector3] = []
@export var snap_distance: float = 0.5
@export var rotation_snap: float = 15.0
@export var physics_force_multiplier: float = 10.0
@export var gravity_zones: Array[Area3D] = []
@export var complete_threshold: float = 0.1

var piece_states: Dictionary = {}
var is_solved: bool = false
var active_piece: RigidBody3D = null
var manipulation_force: float = 100.0

func _ready():
	_initialize_puzzle_pieces()
	_setup_gravity_zones()
	
func _initialize_puzzle_pieces():
	for i in range(puzzle_pieces.size()):
		var piece = puzzle_pieces[i]
		piece_states[piece] = {
			"start_position": piece.position,
			"start_rotation": piece.rotation,
			"is_in_place": false,
			"target_index": i
		}
		piece.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		piece.set_meta("puzzle_piece", true)
		piece.set_meta("piece_index", i)
		
func _setup_gravity_zones():
	for zone in gravity_zones:
		zone.body_entered.connect(_on_gravity_zone_entered)
		zone.body_exited.connect(_on_gravity_zone_exited)
		
func manipulate_piece(piece: RigidBody3D, direction: Vector3):
	if not piece or not piece.has_meta("puzzle_piece"):
		return
		
	active_piece = piece
	piece.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	piece.apply_central_impulse(direction * manipulation_force)
	
func release_piece():
	if active_piece:
		active_piece.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		_check_piece_placement(active_piece)
		active_piece = null
		
func _check_piece_placement(piece: RigidBody3D):
	var state = piece_states.get(piece)
	if not state:
		return
		
	var target_pos = target_positions[state.target_index]
	var distance = piece.position.distance_to(target_pos)
	
	if distance <= snap_distance:
		piece.position = target_pos
		if rotation_snap > 0:
			piece.rotation.y = snappedf(piece.rotation.y, deg_to_rad(rotation_snap))
		state.is_in_place = true
		piece_moved.emit(piece.name, piece.position)
		_check_puzzle_completion()
	else:
		state.is_in_place = false
		
func _check_puzzle_completion():
	var all_in_place = true
	for piece in puzzle_pieces:
		if not piece_states[piece].is_in_place:
			all_in_place = false
			break
			
	if all_in_place and not is_solved:
		is_solved = true
		puzzle_solved.emit()
		_on_puzzle_solved()
		
func _on_puzzle_solved():
	for piece in puzzle_pieces:
		piece.freeze = true
		var tween = create_tween()
		tween.tween_property(piece, "modulate:a", 0.5, 0.5)
		
func reset_puzzle():
	is_solved = false
	for piece in puzzle_pieces:
		var state = piece_states[piece]
		piece.position = state.start_position
		piece.rotation = state.start_rotation
		piece.freeze = false
		piece.modulate.a = 1.0
		state.is_in_place = false
	puzzle_reset.emit()
	
func _on_gravity_zone_entered(body: Node3D):
	if body.has_meta("puzzle_piece"):
		body.gravity_scale = -1.0
		
func _on_gravity_zone_exited(body: Node3D):
	if body.has_meta("puzzle_piece"):
		body.gravity_scale = 1.0
		
func apply_magnetic_force(piece: RigidBody3D, magnet_position: Vector3, strength: float):
	if not piece.has_meta("puzzle_piece"):
		return
		
	var direction = (magnet_position - piece.position).normalized()
	var distance = piece.position.distance_to(magnet_position)
	var force = direction * (strength / max(distance, 1.0))
	piece.apply_central_force(force)