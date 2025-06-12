extends Node

export var max_slots = 30
export var max_stack_size = 99
export var enable_weight_limit = true
export var max_weight = 100.0

var inventory = []
var current_weight = 0.0
var equipped_items = {}

signal item_added(item, amount)
signal item_removed(item, amount)
signal item_equipped(item, slot)
signal item_unequipped(item, slot)
signal inventory_full()
signal weight_limit_reached()

class Item:
	var id = ""
	var name = ""
	var description = ""
	var icon_path = ""
	var weight = 1.0
	var stackable = true
	var max_stack = 99
	var type = "misc"
	var rarity = "common"
	var value = 0
	var properties = {}
	
	func _init(item_id: String, item_name: String):
		id = item_id
		name = item_name

class InventorySlot:
	var item: Item = null
	var quantity = 0
	
	func is_empty() -> bool:
		return item == null or quantity <= 0
	
	func can_add_item(new_item: Item, amount: int) -> bool:
		if is_empty():
			return true
		return item.id == new_item.id and item.stackable and quantity + amount <= item.max_stack
	
	func add_item(new_item: Item, amount: int) -> int:
		if is_empty():
			item = new_item
			quantity = amount
			return amount
		
		if item.id == new_item.id and item.stackable:
			var space_left = item.max_stack - quantity
			var added = min(amount, space_left)
			quantity += added
			return added
		
		return 0
	
	func remove_item(amount: int) -> int:
		var removed = min(amount, quantity)
		quantity -= removed
		
		if quantity <= 0:
			item = null
			quantity = 0
		
		return removed

func _ready():
	_initialize_inventory()
	_load_item_database()

func _initialize_inventory():
	inventory.clear()
	for i in range(max_slots):
		inventory.append(InventorySlot.new())

func add_item(item: Item, amount: int = 1) -> bool:
	if enable_weight_limit:
		var total_weight = item.weight * amount
		if current_weight + total_weight > max_weight:
			emit_signal("weight_limit_reached")
			return false
	
	var remaining = amount
	
	if item.stackable:
		for slot in inventory:
			if slot.can_add_item(item, remaining):
				var added = slot.add_item(item, remaining)
				remaining -= added
				current_weight += item.weight * added
				
				if remaining <= 0:
					break
	
	while remaining > 0:
		var empty_slot = _find_empty_slot()
		if empty_slot == -1:
			emit_signal("inventory_full")
			return false
		
		var to_add = min(remaining, item.max_stack if item.stackable else 1)
		inventory[empty_slot].add_item(item, to_add)
		remaining -= to_add
		current_weight += item.weight * to_add
	
	emit_signal("item_added", item, amount - remaining)
	return remaining == 0

func remove_item(item_id: String, amount: int = 1) -> bool:
	var remaining = amount
	
	for slot in inventory:
		if not slot.is_empty() and slot.item.id == item_id:
			var removed = slot.remove_item(remaining)
			remaining -= removed
			current_weight -= slot.item.weight * removed
			
			if remaining <= 0:
				break
	
	if remaining < amount:
		emit_signal("item_removed", get_item_by_id(item_id), amount - remaining)
		return true
	
	return false

func get_item_count(item_id: String) -> int:
	var count = 0
	for slot in inventory:
		if not slot.is_empty() and slot.item.id == item_id:
			count += slot.quantity
	return count

func has_item(item_id: String, amount: int = 1) -> bool:
	return get_item_count(item_id) >= amount

func equip_item(item_id: String, equip_slot: String) -> bool:
	var slot_index = _find_item_slot(item_id)
	if slot_index == -1:
		return false
	
	var item = inventory[slot_index].item
	
	if not _can_equip_item(item, equip_slot):
		return false
	
	if equipped_items.has(equip_slot):
		unequip_item(equip_slot)
	
	equipped_items[equip_slot] = item
	remove_item(item_id, 1)
	
	emit_signal("item_equipped", item, equip_slot)
	return true

func unequip_item(equip_slot: String) -> bool:
	if not equipped_items.has(equip_slot):
		return false
	
	var item = equipped_items[equip_slot]
	
	if not add_item(item, 1):
		return false
	
	equipped_items.erase(equip_slot)
	emit_signal("item_unequipped", item, equip_slot)
	return true

func get_equipped_item(equip_slot: String) -> Item:
	if equipped_items.has(equip_slot):
		return equipped_items[equip_slot]
	return null

func sort_inventory():
	var items_data = []
	
	for slot in inventory:
		if not slot.is_empty():
			items_data.append({
				"item": slot.item,
				"quantity": slot.quantity
			})
	
	items_data.sort_custom(self, "_sort_items")
	
	_initialize_inventory()
	
	for data in items_data:
		add_item(data.item, data.quantity)

func _sort_items(a, b) -> bool:
	if a.item.type != b.item.type:
		return a.item.type < b.item.type
	
	var rarity_order = ["common", "uncommon", "rare", "epic", "legendary"]
	var a_rarity = rarity_order.find(a.item.rarity)
	var b_rarity = rarity_order.find(b.item.rarity)
	
	if a_rarity != b_rarity:
		return a_rarity > b_rarity
	
	return a.item.name < b.item.name

func clear_inventory():
	_initialize_inventory()
	current_weight = 0.0
	equipped_items.clear()

func save_inventory() -> Dictionary:
	var save_data = {
		"slots": [],
		"equipped": {},
		"weight": current_weight
	}
	
	for slot in inventory:
		if slot.is_empty():
			save_data.slots.append(null)
		else:
			save_data.slots.append({
				"item_id": slot.item.id,
				"quantity": slot.quantity
			})
	
	for equip_slot in equipped_items:
		save_data.equipped[equip_slot] = equipped_items[equip_slot].id
	
	return save_data

func load_inventory(save_data: Dictionary):
	clear_inventory()
	
	if save_data.has("slots"):
		for i in range(min(save_data.slots.size(), inventory.size())):
			var slot_data = save_data.slots[i]
			if slot_data != null:
				var item = get_item_by_id(slot_data.item_id)
				if item:
					inventory[i].add_item(item, slot_data.quantity)
	
	if save_data.has("equipped"):
		for equip_slot in save_data.equipped:
			var item = get_item_by_id(save_data.equipped[equip_slot])
			if item:
				equipped_items[equip_slot] = item
	
	if save_data.has("weight"):
		current_weight = save_data.weight
	else:
		_recalculate_weight()

func _find_empty_slot() -> int:
	for i in range(inventory.size()):
		if inventory[i].is_empty():
			return i
	return -1

func _find_item_slot(item_id: String) -> int:
	for i in range(inventory.size()):
		if not inventory[i].is_empty() and inventory[i].item.id == item_id:
			return i
	return -1

func _can_equip_item(item: Item, equip_slot: String) -> bool:
	match equip_slot:
		"weapon":
			return item.type == "weapon"
		"armor":
			return item.type == "armor"
		"accessory":
			return item.type == "accessory"
		_:
			return false

func _recalculate_weight():
	current_weight = 0.0
	for slot in inventory:
		if not slot.is_empty():
			current_weight += slot.item.weight * slot.quantity

func get_item_by_id(item_id: String) -> Item:
	return ItemDatabase.get_item(item_id)

func _load_item_database():
	pass

class ItemDatabase:
	static func get_item(item_id: String) -> Item:
		var item = Item.new(item_id, item_id.capitalize().replace("_", " "))
		
		match item_id:
			"health_potion":
				item.weight = 0.5
				item.type = "consumable"
				item.value = 50
			"sword":
				item.weight = 3.0
				item.type = "weapon"
				item.stackable = false
				item.rarity = "uncommon"
				item.value = 200
			"leather_armor":
				item.weight = 5.0
				item.type = "armor"
				item.stackable = false
				item.rarity = "common"
				item.value = 150
			_:
				pass
		
		return item