extends Node

class_name InventorySystem

@export var max_slots: int = 20
@export var stack_limit: int = 99

var items: Array[InventoryItem] = []
var selected_slot: int = 0

signal item_added(item: InventoryItem, slot: int)
signal item_removed(item: InventoryItem, slot: int)
signal item_used(item: InventoryItem, slot: int)
signal inventory_full()
signal slot_selected(slot: int)

class InventoryItem:
	var id: String
	var name: String
	var description: String
	var icon: Texture2D
	var quantity: int = 1
	var max_stack: int = 1
	var item_type: String = "misc"
	var consumable: bool = false
	var data: Dictionary = {}
	
	func _init(item_id: String = "", item_name: String = "", item_desc: String = ""):
		id = item_id
		name = item_name
		description = item_desc
	
	func can_stack_with(other_item: InventoryItem) -> bool:
		return id == other_item.id and quantity + other_item.quantity <= max_stack
	
	func split_stack(amount: int) -> InventoryItem:
		if amount >= quantity:
			return null
		
		var new_item = InventoryItem.new(id, name, description)
		new_item.icon = icon
		new_item.max_stack = max_stack
		new_item.item_type = item_type
		new_item.consumable = consumable
		new_item.data = data.duplicate()
		new_item.quantity = amount
		
		quantity -= amount
		return new_item

func _ready():
	items.resize(max_slots)

func add_item(item: InventoryItem) -> bool:
	if not item:
		return false
	
	var remaining_quantity = item.quantity
	
	for i in range(max_slots):
		if items[i] and items[i].can_stack_with(item):
			var space_available = items[i].max_stack - items[i].quantity
			var amount_to_add = min(remaining_quantity, space_available)
			
			items[i].quantity += amount_to_add
			remaining_quantity -= amount_to_add
			
			if remaining_quantity <= 0:
				item_added.emit(item, i)
				return true
	
	for i in range(max_slots):
		if not items[i]:
			var new_item = InventoryItem.new(item.id, item.name, item.description)
			new_item.icon = item.icon
			new_item.max_stack = item.max_stack
			new_item.item_type = item.item_type
			new_item.consumable = item.consumable
			new_item.data = item.data.duplicate()
			new_item.quantity = min(remaining_quantity, new_item.max_stack)
			
			items[i] = new_item
			remaining_quantity -= new_item.quantity
			item_added.emit(new_item, i)
			
			if remaining_quantity <= 0:
				return true
	
	inventory_full.emit()
	return false

func remove_item(slot: int, amount: int = 1) -> InventoryItem:
	if slot < 0 or slot >= max_slots or not items[slot]:
		return null
	
	var item = items[slot]
	var removed_item: InventoryItem = null
	
	if amount >= item.quantity:
		removed_item = item
		items[slot] = null
	else:
		removed_item = item.split_stack(amount)
	
	item_removed.emit(removed_item, slot)
	return removed_item

func use_item(slot: int) -> bool:
	if slot < 0 or slot >= max_slots or not items[slot]:
		return false
	
	var item = items[slot]
	
	if not item.consumable:
		return false
	
	item_used.emit(item, slot)
	
	match item.item_type:
		"health_potion":
			restore_health(item.data.get("heal_amount", 20))
		"mana_potion":
			restore_mana(item.data.get("mana_amount", 15))
		"food":
			restore_hunger(item.data.get("hunger_amount", 10))
		"key":
			return use_key(item)
	
	item.quantity -= 1
	if item.quantity <= 0:
		items[slot] = null
	
	return true

func move_item(from_slot: int, to_slot: int) -> bool:
	if from_slot < 0 or from_slot >= max_slots or to_slot < 0 or to_slot >= max_slots:
		return false
	
	if from_slot == to_slot:
		return true
	
	var from_item = items[from_slot]
	var to_item = items[to_slot]
	
	if not from_item:
		return false
	
	if not to_item:
		items[to_slot] = from_item
		items[from_slot] = null
		return true
	
	if from_item.can_stack_with(to_item):
		var space_available = to_item.max_stack - to_item.quantity
		var amount_to_move = min(from_item.quantity, space_available)
		
		to_item.quantity += amount_to_move
		from_item.quantity -= amount_to_move
		
		if from_item.quantity <= 0:
			items[from_slot] = null
		
		return true
	else:
		items[from_slot] = to_item
		items[to_slot] = from_item
		return true

func has_item(item_id: String, required_amount: int = 1) -> bool:
	var total_count = 0
	
	for item in items:
		if item and item.id == item_id:
			total_count += item.quantity
			if total_count >= required_amount:
				return true
	
	return false

func get_item_count(item_id: String) -> int:
	var total_count = 0
	
	for item in items:
		if item and item.id == item_id:
			total_count += item.quantity
	
	return total_count

func consume_item(item_id: String, amount: int = 1) -> bool:
	if not has_item(item_id, amount):
		return false
	
	var remaining_to_consume = amount
	
	for i in range(max_slots):
		if remaining_to_consume <= 0:
			break
		
		var item = items[i]
		if item and item.id == item_id:
			var consume_from_stack = min(item.quantity, remaining_to_consume)
			item.quantity -= consume_from_stack
			remaining_to_consume -= consume_from_stack
			
			if item.quantity <= 0:
				items[i] = null
	
	return true

func select_slot(slot: int):
	if slot >= 0 and slot < max_slots:
		selected_slot = slot
		slot_selected.emit(slot)

func get_selected_item() -> InventoryItem:
	return items[selected_slot] if selected_slot < max_slots else null

func get_item_at_slot(slot: int) -> InventoryItem:
	if slot >= 0 and slot < max_slots:
		return items[slot]
	return null

func is_slot_empty(slot: int) -> bool:
	return slot >= 0 and slot < max_slots and items[slot] == null

func get_empty_slot_count() -> int:
	var count = 0
	for item in items:
		if not item:
			count += 1
	return count

func clear_inventory():
	for i in range(max_slots):
		items[i] = null

func restore_health(amount: int):
	var player = get_tree().get_first_node_in_group("player")
	if player and player.has_method("heal"):
		player.heal(amount)

func restore_mana(amount: int):
	var player = get_tree().get_first_node_in_group("player")
	if player and player.has_method("restore_mana"):
		player.restore_mana(amount)

func restore_hunger(amount: int):
	var player = get_tree().get_first_node_in_group("player")
	if player and player.has_method("restore_hunger"):
		player.restore_hunger(amount)

func use_key(key_item: InventoryItem) -> bool:
	var doors = get_tree().get_nodes_in_group("doors")
	
	for door in doors:
		if door.has_method("try_unlock") and door.try_unlock(key_item.id):
			return true
	
	return false