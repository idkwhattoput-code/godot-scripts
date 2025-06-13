extends CharacterBody3D

signal shop_opened(shop_inventory: Array)
signal shop_closed
signal item_purchased(item: Dictionary, price: int)
signal item_sold(item: Dictionary, price: int)
signal dialogue_started(npc_name: String)
signal dialogue_ended

@export_group("Shop Configuration")
@export var shop_name: String = "General Store"
@export var npc_name: String = "Shopkeeper"
@export var shop_inventory: Array[Resource] = []
@export var buy_price_multiplier: float = 1.0
@export var sell_price_multiplier: float = 0.5
@export var restock_interval: float = 300.0
@export var max_stock_per_item: int = 10

@export_group("Interaction")
@export var interaction_range: float = 3.0
@export var greeting_messages: Array[String] = ["Welcome to my shop!", "Looking to buy something?", "Best prices in town!"]
@export var farewell_messages: Array[String] = ["Come back anytime!", "Thank you for your business!", "Safe travels!"]
@export var no_money_messages: Array[String] = ["You don't have enough gold.", "Sorry, that's too expensive for you.", "Come back when you have more coin."]

@export_group("Behavior")
@export var wander_radius: float = 5.0
@export var wander_speed: float = 2.0
@export var idle_time_range: Vector2 = Vector2(3.0, 8.0)
@export var look_at_customer: bool = true
@export var return_to_shop_distance: float = 10.0

@export_group("Visual")
@export var animation_player: AnimationPlayer
@export var shop_ui_scene: PackedScene
@export var interaction_indicator: Node3D
@export var speech_bubble: Node3D

var shop_inventory_data: Array[Dictionary] = []
var current_customer: Node3D = null
var is_shop_open: bool = false
var home_position: Vector3
var current_state: NPCState = NPCState.IDLE
var state_timer: float = 0.0
var interaction_area: Area3D
var restock_timer: float = 0.0
var dialogue_options: Array[Dictionary] = []

enum NPCState {
	IDLE,
	WANDERING,
	TALKING,
	RETURNING_HOME
}

func _ready():
	home_position = global_position
	_setup_interaction_area()
	_initialize_shop_inventory()
	_setup_dialogue_options()
	
	if interaction_indicator:
		interaction_indicator.visible = false
		
func _setup_interaction_area():
	interaction_area = Area3D.new()
	interaction_area.collision_layer = 0
	interaction_area.collision_mask = 1
	
	var collision_shape = CollisionShape3D.new()
	var sphere_shape = SphereShape3D.new()
	sphere_shape.radius = interaction_range
	collision_shape.shape = sphere_shape
	
	interaction_area.add_child(collision_shape)
	add_child(interaction_area)
	
	interaction_area.body_entered.connect(_on_customer_entered)
	interaction_area.body_exited.connect(_on_customer_exited)
	
func _initialize_shop_inventory():
	shop_inventory_data.clear()
	
	for item_resource in shop_inventory:
		if item_resource and item_resource.has_method("get_item_data"):
			var item_data = item_resource.get_item_data()
			item_data["stock"] = randi_range(1, max_stock_per_item)
			item_data["base_price"] = item_data.get("price", 10)
			item_data["buy_price"] = int(item_data["base_price"] * buy_price_multiplier)
			item_data["sell_price"] = int(item_data["base_price"] * sell_price_multiplier)
			shop_inventory_data.append(item_data)
			
func _setup_dialogue_options():
	dialogue_options = [
		{
			"text": "I'd like to buy something.",
			"action": "open_shop"
		},
		{
			"text": "I have items to sell.",
			"action": "open_sell_menu"
		},
		{
			"text": "Tell me about this place.",
			"action": "talk_lore"
		},
		{
			"text": "Goodbye.",
			"action": "end_conversation"
		}
	]
	
func _physics_process(delta):
	restock_timer += delta
	if restock_timer >= restock_interval:
		_restock_shop()
		restock_timer = 0.0
		
	match current_state:
		NPCState.IDLE:
			_process_idle(delta)
		NPCState.WANDERING:
			_process_wandering(delta)
		NPCState.TALKING:
			_process_talking(delta)
		NPCState.RETURNING_HOME:
			_process_returning_home(delta)
			
	move_and_slide()
	
func _process_idle(delta):
	state_timer -= delta
	if state_timer <= 0:
		if randf() < 0.3 and not is_shop_open:
			_start_wandering()
		else:
			state_timer = randf_range(idle_time_range.x, idle_time_range.y)
			
	if look_at_customer and current_customer:
		_look_at_target(current_customer.global_position)
		
func _process_wandering(delta):
	if global_position.distance_to(home_position) > return_to_shop_distance:
		current_state = NPCState.RETURNING_HOME
		return
		
	var distance_to_target = global_position.distance_to(get_meta("wander_target", global_position))
	if distance_to_target < 0.5:
		current_state = NPCState.IDLE
		state_timer = randf_range(idle_time_range.x, idle_time_range.y)
		velocity = Vector3.ZERO
		
		if animation_player:
			animation_player.play("idle")
			
func _process_talking(delta):
	if current_customer:
		_look_at_target(current_customer.global_position)
		
func _process_returning_home(delta):
	var direction = (home_position - global_position).normalized()
	velocity = direction * wander_speed
	
	if global_position.distance_to(home_position) < 0.5:
		current_state = NPCState.IDLE
		state_timer = randf_range(idle_time_range.x, idle_time_range.y)
		velocity = Vector3.ZERO
		
		if animation_player:
			animation_player.play("idle")
			
func _start_wandering():
	current_state = NPCState.WANDERING
	
	var random_angle = randf() * TAU
	var random_distance = randf_range(1, wander_radius)
	var wander_target = home_position + Vector3(
		cos(random_angle) * random_distance,
		0,
		sin(random_angle) * random_distance
	)
	
	set_meta("wander_target", wander_target)
	
	var direction = (wander_target - global_position).normalized()
	velocity = direction * wander_speed
	
	if animation_player:
		animation_player.play("walk")
		
func _look_at_target(target_position: Vector3):
	var look_direction = (target_position - global_position).normalized()
	look_direction.y = 0
	
	if look_direction.length() > 0:
		var target_transform = transform.looking_at(global_position + look_direction, Vector3.UP)
		transform = transform.interpolate_with(target_transform, 0.1)
		
func _on_customer_entered(body: Node3D):
	if body.is_in_group("player") and not current_customer:
		current_customer = body
		if interaction_indicator:
			interaction_indicator.visible = true
			
		_greet_customer()
		
func _on_customer_exited(body: Node3D):
	if body == current_customer:
		current_customer = null
		if interaction_indicator:
			interaction_indicator.visible = false
			
		if is_shop_open:
			close_shop()
			
func _greet_customer():
	if greeting_messages.size() > 0:
		var greeting = greeting_messages[randi() % greeting_messages.size()]
		_show_speech_bubble(greeting, 3.0)
		
func interact():
	if not current_customer or is_shop_open:
		return
		
	current_state = NPCState.TALKING
	dialogue_started.emit(npc_name)
	
	_show_dialogue_options()
	
func _show_dialogue_options():
	if current_customer and current_customer.has_method("show_dialogue_options"):
		current_customer.show_dialogue_options(dialogue_options)
		
func handle_dialogue_choice(choice: String):
	match choice:
		"open_shop":
			open_shop()
		"open_sell_menu":
			open_sell_menu()
		"talk_lore":
			_tell_lore()
		"end_conversation":
			end_conversation()
			
func open_shop():
	if not current_customer:
		return
		
	is_shop_open = true
	shop_opened.emit(shop_inventory_data)
	
	if shop_ui_scene and current_customer.has_method("show_shop_ui"):
		var shop_ui = shop_ui_scene.instantiate()
		current_customer.show_shop_ui(shop_ui, shop_inventory_data)
		
func open_sell_menu():
	if not current_customer or not current_customer.has_method("get_inventory"):
		return
		
	var player_inventory = current_customer.get_inventory()
	
	if shop_ui_scene and current_customer.has_method("show_sell_ui"):
		var sell_ui = shop_ui_scene.instantiate()
		current_customer.show_sell_ui(sell_ui, player_inventory, sell_price_multiplier)
		
func close_shop():
	is_shop_open = false
	shop_closed.emit()
	
	var farewell = farewell_messages[randi() % farewell_messages.size()]
	_show_speech_bubble(farewell, 2.0)
	
	current_state = NPCState.IDLE
	state_timer = randf_range(idle_time_range.x, idle_time_range.y)
	
func purchase_item(item_index: int) -> bool:
	if item_index < 0 or item_index >= shop_inventory_data.size():
		return false
		
	var item = shop_inventory_data[item_index]
	
	if item["stock"] <= 0:
		_show_speech_bubble("Sorry, that item is out of stock.", 2.0)
		return false
		
	if not current_customer.has_method("remove_gold"):
		return false
		
	var price = item["buy_price"]
	if current_customer.has_method("get_gold") and current_customer.get_gold() < price:
		var no_money_msg = no_money_messages[randi() % no_money_messages.size()]
		_show_speech_bubble(no_money_msg, 2.0)
		return false
		
	if current_customer.remove_gold(price):
		item["stock"] -= 1
		item_purchased.emit(item, price)
		
		if current_customer.has_method("add_item"):
			current_customer.add_item(item)
			
		_show_speech_bubble("Thank you for your purchase!", 2.0)
		return true
		
	return false
	
func sell_item(item: Dictionary) -> bool:
	if not current_customer or not current_customer.has_method("add_gold"):
		return false
		
	var sell_price = int(item.get("base_price", 10) * sell_price_multiplier)
	
	current_customer.add_gold(sell_price)
	item_sold.emit(item, sell_price)
	
	var existing_item = _find_item_in_inventory(item["name"])
	if existing_item:
		existing_item["stock"] += 1
	else:
		item["stock"] = 1
		item["buy_price"] = int(item.get("base_price", 10) * buy_price_multiplier)
		item["sell_price"] = sell_price
		shop_inventory_data.append(item)
		
	_show_speech_bubble("I'll take that off your hands.", 2.0)
	return true
	
func _find_item_in_inventory(item_name: String) -> Dictionary:
	for item in shop_inventory_data:
		if item["name"] == item_name:
			return item
	return {}
	
func _tell_lore():
	var lore_messages = [
		"This shop has been in my family for generations.",
		"Business has been slow lately with all the monsters around.",
		"I get my supplies from traders who pass through town.",
		"If you're looking for rare items, check back after a few days."
	]
	
	var lore = lore_messages[randi() % lore_messages.size()]
	_show_speech_bubble(lore, 4.0)
	
func end_conversation():
	dialogue_ended.emit()
	current_state = NPCState.IDLE
	state_timer = randf_range(idle_time_range.x, idle_time_range.y)
	
func _restock_shop():
	for item in shop_inventory_data:
		if item["stock"] < max_stock_per_item:
			item["stock"] += randi_range(1, 3)
			item["stock"] = min(item["stock"], max_stock_per_item)
			
func _show_speech_bubble(text: String, duration: float):
	if speech_bubble and speech_bubble.has_method("show_text"):
		speech_bubble.show_text(text, duration)
		
func get_shop_data() -> Dictionary:
	return {
		"name": shop_name,
		"inventory": shop_inventory_data,
		"is_open": is_shop_open
	}