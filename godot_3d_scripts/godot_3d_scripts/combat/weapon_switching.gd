extends Node

export var switch_speed = 0.3
export var weapon_slots = 3
export var quick_switch_enabled = true
export var drop_current_weapon = false

signal weapon_switched(old_weapon, new_weapon)
signal weapon_equipped(weapon)
signal weapon_holstered(weapon)
signal switching_started()
signal switching_completed()

var weapons = []
var current_weapon_index = -1
var previous_weapon_index = -1
var is_switching = false
var switch_timer = 0.0

onready var weapon_holder = $WeaponHolder
onready var switch_sound = $SwitchSound
onready var holster_sound = $HolsterSound
onready var draw_sound = $DrawSound

func _ready():
	_initialize_weapon_slots()
	_find_existing_weapons()

func _physics_process(delta):
	if is_switching:
		switch_timer -= delta
		if switch_timer <= 0:
			_complete_switch()

func _input(event):
	if is_switching:
		return
		
	if event.is_action_pressed("weapon_1"):
		switch_to_weapon(0)
	elif event.is_action_pressed("weapon_2"):
		switch_to_weapon(1)
	elif event.is_action_pressed("weapon_3"):
		switch_to_weapon(2)
	elif event.is_action_pressed("next_weapon"):
		cycle_weapon(1)
	elif event.is_action_pressed("previous_weapon"):
		cycle_weapon(-1)
	elif event.is_action_pressed("quick_switch") and quick_switch_enabled:
		quick_switch()
	elif event.is_action_pressed("holster_weapon"):
		holster_current_weapon()

func _initialize_weapon_slots():
	weapons.resize(weapon_slots)
	for i in range(weapon_slots):
		weapons[i] = null

func _find_existing_weapons():
	if not weapon_holder:
		return
		
	var index = 0
	for child in weapon_holder.get_children():
		if child.has_method("get_weapon_name") and index < weapon_slots:
			weapons[index] = child
			child.visible = false
			index += 1
	
	if weapons[0]:
		switch_to_weapon(0)

func add_weapon(weapon_scene, slot = -1):
	if slot == -1:
		slot = _find_empty_slot()
		
	if slot == -1 or slot >= weapon_slots:
		return false
		
	if weapons[slot]:
		if drop_current_weapon:
			drop_weapon(slot)
		else:
			return false
	
	var weapon = weapon_scene.instance()
	weapon_holder.add_child(weapon)
	weapons[slot] = weapon
	weapon.visible = false
	
	if current_weapon_index == -1:
		switch_to_weapon(slot)
		
	return true

func _find_empty_slot():
	for i in range(weapon_slots):
		if not weapons[i]:
			return i
	return -1

func switch_to_weapon(index):
	if index < 0 or index >= weapon_slots or not weapons[index]:
		return
		
	if index == current_weapon_index or is_switching:
		return
	
	_start_switch(index)

func _start_switch(new_index):
	is_switching = true
	switch_timer = switch_speed
	
	emit_signal("switching_started")
	
	if switch_sound:
		switch_sound.play()
	
	if current_weapon_index >= 0 and weapons[current_weapon_index]:
		_holster_weapon(current_weapon_index)
	
	previous_weapon_index = current_weapon_index
	current_weapon_index = new_index

func _complete_switch():
	is_switching = false
	
	if weapons[current_weapon_index]:
		_equip_weapon(current_weapon_index)
		
	emit_signal("switching_completed")
	emit_signal("weapon_switched", 
		weapons[previous_weapon_index] if previous_weapon_index >= 0 else null,
		weapons[current_weapon_index]
	)

func _holster_weapon(index):
	if not weapons[index]:
		return
		
	weapons[index].visible = false
	
	if weapons[index].has_method("on_holster"):
		weapons[index].on_holster()
		
	if holster_sound:
		holster_sound.play()
		
	emit_signal("weapon_holstered", weapons[index])

func _equip_weapon(index):
	if not weapons[index]:
		return
		
	weapons[index].visible = true
	
	if weapons[index].has_method("on_equip"):
		weapons[index].on_equip()
		
	if draw_sound:
		draw_sound.play()
		
	emit_signal("weapon_equipped", weapons[index])

func cycle_weapon(direction):
	if weapon_slots <= 1:
		return
		
	var next_index = current_weapon_index
	var attempts = 0
	
	while attempts < weapon_slots:
		next_index = (next_index + direction + weapon_slots) % weapon_slots
		if weapons[next_index]:
			switch_to_weapon(next_index)
			break
		attempts += 1

func quick_switch():
	if previous_weapon_index >= 0 and weapons[previous_weapon_index]:
		switch_to_weapon(previous_weapon_index)

func holster_current_weapon():
	if current_weapon_index >= 0 and not is_switching:
		_holster_weapon(current_weapon_index)
		previous_weapon_index = current_weapon_index
		current_weapon_index = -1

func drop_weapon(index = -1):
	if index == -1:
		index = current_weapon_index
		
	if index < 0 or index >= weapon_slots or not weapons[index]:
		return
		
	var weapon = weapons[index]
	weapons[index] = null
	
	if weapon.has_method("on_drop"):
		weapon.on_drop()
	
	weapon_holder.remove_child(weapon)
	
	var dropped_item = weapon
	get_tree().current_scene.add_child(dropped_item)
	dropped_item.global_transform = weapon_holder.global_transform
	
	if dropped_item is RigidBody:
		dropped_item.apply_central_impulse(Vector3(0, 2, -5))
	
	if index == current_weapon_index:
		current_weapon_index = -1
		for i in range(weapon_slots):
			if weapons[i]:
				switch_to_weapon(i)
				break

func get_current_weapon():
	if current_weapon_index >= 0:
		return weapons[current_weapon_index]
	return null

func has_weapon(weapon_name):
	for weapon in weapons:
		if weapon and weapon.has_method("get_weapon_name"):
			if weapon.get_weapon_name() == weapon_name:
				return true
	return false

func get_weapon_in_slot(slot):
	if slot >= 0 and slot < weapon_slots:
		return weapons[slot]
	return null

func is_slot_empty(slot):
	return slot >= 0 and slot < weapon_slots and not weapons[slot]

func clear_all_weapons():
	for i in range(weapon_slots):
		if weapons[i]:
			weapons[i].queue_free()
			weapons[i] = null
	current_weapon_index = -1
	previous_weapon_index = -1