extends Control

export var shop_name = "General Store"
export var buy_price_multiplier = 1.0
export var sell_price_multiplier = 0.5
export var tax_rate = 0.05
export var enable_buyback = true
export var buyback_limit = 20
export var enable_item_preview = true

var shop_inventory = []
var player_inventory = []
var buyback_items = []
var player_gold = 1000
var selected_item = null
var selected_tab = "buy"
var cart_items = []
var cart_total = 0

onready var shop_name_label = $HeaderPanel/ShopNameLabel
onready var player_gold_label = $HeaderPanel/GoldLabel
onready var tab_container = $MainPanel/TabContainer
onready var buy_tab = $MainPanel/TabContainer/BuyTab
onready var sell_tab = $MainPanel/TabContainer/SellTab
onready var buyback_tab = $MainPanel/TabContainer/BuybackTab
onready var item_list = $MainPanel/TabContainer/BuyTab/ItemList
onready var sell_list = $MainPanel/TabContainer/SellTab/ItemList
onready var buyback_list = $MainPanel/TabContainer/BuybackTab/ItemList
onready var item_preview = $SidePanel/ItemPreview
onready var item_info = $SidePanel/ItemInfo
onready var quantity_spin = $SidePanel/QuantityContainer/QuantitySpinBox
onready var price_label = $SidePanel/PriceLabel
onready var buy_button = $SidePanel/ActionButtons/BuyButton
onready var sell_button = $SidePanel/ActionButtons/SellButton
onready var cart_panel = $CartPanel
onready var cart_list = $CartPanel/CartList
onready var cart_total_label = $CartPanel/TotalLabel
onready var checkout_button = $CartPanel/CheckoutButton
onready var clear_cart_button = $CartPanel/ClearCartButton
onready var search_bar = $MainPanel/SearchBar
onready var filter_options = $MainPanel/FilterOptions

signal item_purchased(item, quantity)
signal item_sold(item, quantity)
signal transaction_completed(items, total)
signal shop_closed()

class ShopItem:
	var id: String = ""
	var name: String = ""
	var description: String = ""
	var icon_path: String = ""
	var base_price: int = 0
	var current_price: int = 0
	var quantity: int = -1  # -1 means infinite
	var category: String = "misc"
	var rarity: String = "common"
	var level_requirement: int = 0
	var stats: Dictionary = {}
	var is_on_sale: bool = false
	var sale_percentage: float = 0.0
	
	func get_buy_price(multiplier: float = 1.0) -> int:
		var price = current_price * multiplier
		if is_on_sale:
			price *= (1.0 - sale_percentage)
		return int(price)
	
	func get_sell_price(multiplier: float = 0.5) -> int:
		return int(base_price * multiplier)

func _ready():
	_setup_ui()
	_connect_signals()
	_populate_shop()
	_update_display()

func _setup_ui():
	shop_name_label.text = shop_name
	_update_gold_display()
	
	if not enable_buyback:
		buyback_tab.queue_free()
	
	cart_panel.hide()
	
	buy_button.text = "Add to Cart"
	sell_button.text = "Sell"
	
	quantity_spin.min_value = 1
	quantity_spin.value = 1

func _connect_signals():
	tab_container.connect("tab_changed", self, "_on_tab_changed")
	item_list.connect("item_selected", self, "_on_item_selected", ["buy"])
	sell_list.connect("item_selected", self, "_on_item_selected", ["sell"])
	buyback_list.connect("item_selected", self, "_on_item_selected", ["buyback"])
	
	quantity_spin.connect("value_changed", self, "_on_quantity_changed")
	buy_button.connect("pressed", self, "_on_buy_pressed")
	sell_button.connect("pressed", self, "_on_sell_pressed")
	
	checkout_button.connect("pressed", self, "_on_checkout_pressed")
	clear_cart_button.connect("pressed", self, "_on_clear_cart_pressed")
	
	search_bar.connect("text_changed", self, "_on_search_changed")
	filter_options.connect("item_selected", self, "_on_filter_changed")

func _populate_shop():
	shop_inventory.clear()
	
	# Add sample items
	var items = [
		_create_item("health_potion", "Health Potion", "Restores 50 HP", 50, "consumable"),
		_create_item("mana_potion", "Mana Potion", "Restores 30 MP", 75, "consumable"),
		_create_item("iron_sword", "Iron Sword", "A basic iron sword", 200, "weapon"),
		_create_item("leather_armor", "Leather Armor", "Light protective gear", 150, "armor"),
		_create_item("magic_ring", "Magic Ring", "Increases mana by 20", 500, "accessory"),
		_create_item("teleport_scroll", "Teleport Scroll", "Return to town", 100, "consumable")
	]
	
	for item in items:
		shop_inventory.append(item)
	
	# Set some items on sale
	if shop_inventory.size() > 2:
		shop_inventory[2].is_on_sale = true
		shop_inventory[2].sale_percentage = 0.2

func _create_item(id: String, name: String, desc: String, price: int, category: String) -> ShopItem:
	var item = ShopItem.new()
	item.id = id
	item.name = name
	item.description = desc
	item.base_price = price
	item.current_price = price
	item.category = category
	return item

func _update_display():
	_clear_lists()
	
	match selected_tab:
		"buy":
			_populate_buy_list()
		"sell":
			_populate_sell_list()
		"buyback":
			_populate_buyback_list()

func _clear_lists():
	item_list.clear()
	sell_list.clear()
	buyback_list.clear()

func _populate_buy_list():
	for item in shop_inventory:
		if _should_show_item(item):
			_add_item_to_list(item_list, item, "buy")

func _populate_sell_list():
	for item in player_inventory:
		if _should_show_item(item):
			_add_item_to_list(sell_list, item, "sell")

func _populate_buyback_list():
	for item in buyback_items:
		_add_item_to_list(buyback_list, item, "buyback")

func _add_item_to_list(list: ItemList, item: ShopItem, mode: String):
	var item_text = item.name
	
	if item.quantity > 0 and item.quantity != -1:
		item_text += " (%d)" % item.quantity
	
	var price = 0
	match mode:
		"buy":
			price = item.get_buy_price(buy_price_multiplier)
			if item.is_on_sale:
				item_text += " [SALE]"
		"sell":
			price = item.get_sell_price(sell_price_multiplier)
		"buyback":
			price = item.get_buy_price(buy_price_multiplier)
	
	item_text += " - %dg" % price
	
	list.add_item(item_text)
	
	var index = list.get_item_count() - 1
	list.set_item_metadata(index, item)
	
	# Set item color based on rarity
	match item.rarity:
		"common":
			list.set_item_custom_fg_color(index, Color.white)
		"uncommon":
			list.set_item_custom_fg_color(index, Color.green)
		"rare":
			list.set_item_custom_fg_color(index, Color.blue)
		"epic":
			list.set_item_custom_fg_color(index, Color.purple)
		"legendary":
			list.set_item_custom_fg_color(index, Color.orange)

func _should_show_item(item: ShopItem) -> bool:
	var search_text = search_bar.text.to_lower()
	if search_text != "" and not item.name.to_lower().find(search_text) != -1:
		return false
	
	var selected_filter = filter_options.get_selected_id()
	if selected_filter > 0:  # 0 is "All"
		var filter_category = filter_options.get_item_text(selected_filter).to_lower()
		if item.category != filter_category:
			return false
	
	return true

func _on_tab_changed(tab: int):
	match tab:
		0:
			selected_tab = "buy"
			buy_button.show()
			sell_button.hide()
		1:
			selected_tab = "sell"
			buy_button.hide()
			sell_button.show()
		2:
			selected_tab = "buyback"
			buy_button.show()
			sell_button.hide()
	
	selected_item = null
	_update_display()
	_update_selection_info()

func _on_item_selected(index: int, mode: String):
	var list = null
	match mode:
		"buy":
			list = item_list
		"sell":
			list = sell_list
		"buyback":
			list = buyback_list
	
	if list and index < list.get_item_count():
		selected_item = list.get_item_metadata(index)
		_update_selection_info()

func _update_selection_info():
	if not selected_item:
		item_info.text = "Select an item"
		price_label.text = "Price: -"
		buy_button.disabled = true
		sell_button.disabled = true
		quantity_spin.editable = false
		return
	
	item_info.clear()
	item_info.add_text(selected_item.name + "\n")
	item_info.push_color(Color(0.7, 0.7, 0.7))
	item_info.add_text(selected_item.description + "\n\n")
	item_info.pop()
	
	if selected_item.stats.size() > 0:
		item_info.add_text("Stats:\n")
		for stat in selected_item.stats:
			item_info.add_text("  %s: %+d\n" % [stat.capitalize(), selected_item.stats[stat]])
	
	if selected_item.level_requirement > 0:
		item_info.add_text("\nRequired Level: %d" % selected_item.level_requirement)
	
	_update_price_display()
	
	buy_button.disabled = false
	sell_button.disabled = false
	quantity_spin.editable = true
	
	if selected_item.quantity > 0 and selected_item.quantity != -1:
		quantity_spin.max_value = selected_item.quantity
	else:
		quantity_spin.max_value = 99

func _update_price_display():
	if not selected_item:
		return
	
	var quantity = int(quantity_spin.value)
	var total_price = 0
	
	match selected_tab:
		"buy", "buyback":
			total_price = selected_item.get_buy_price(buy_price_multiplier) * quantity
			var tax = int(total_price * tax_rate)
			price_label.text = "Price: %dg (+ %dg tax)" % [total_price, tax]
			total_price += tax
		"sell":
			total_price = selected_item.get_sell_price(sell_price_multiplier) * quantity
			price_label.text = "Sell Price: %dg" % total_price

func _on_quantity_changed(value: float):
	_update_price_display()

func _on_buy_pressed():
	if not selected_item:
		return
	
	var quantity = int(quantity_spin.value)
	var total_price = selected_item.get_buy_price(buy_price_multiplier) * quantity
	total_price += int(total_price * tax_rate)
	
	if player_gold < total_price:
		_show_message("Not enough gold!")
		return
	
	# Add to cart
	var cart_item = {
		"item": selected_item,
		"quantity": quantity,
		"price": total_price
	}
	cart_items.append(cart_item)
	_update_cart_display()
	
	cart_panel.show()

func _on_sell_pressed():
	if not selected_item:
		return
	
	var quantity = int(quantity_spin.value)
	var total_price = selected_item.get_sell_price(sell_price_multiplier) * quantity
	
	# Process sale immediately
	player_gold += total_price
	
	# Add to buyback
	if enable_buyback:
		buyback_items.append(selected_item)
		if buyback_items.size() > buyback_limit:
			buyback_items.pop_front()
	
	# Remove from player inventory
	player_inventory.erase(selected_item)
	
	emit_signal("item_sold", selected_item, quantity)
	
	_update_gold_display()
	_update_display()
	_show_message("Sold %s x%d for %dg" % [selected_item.name, quantity, total_price])

func _update_cart_display():
	cart_list.clear()
	cart_total = 0
	
	for cart_item in cart_items:
		var text = "%s x%d - %dg" % [cart_item.item.name, cart_item.quantity, cart_item.price]
		cart_list.add_item(text)
		cart_total += cart_item.price
	
	cart_total_label.text = "Total: %dg" % cart_total
	checkout_button.disabled = cart_total > player_gold

func _on_checkout_pressed():
	if cart_items.empty() or cart_total > player_gold:
		return
	
	# Process all cart items
	player_gold -= cart_total
	
	var purchased_items = []
	for cart_item in cart_items:
		var item = cart_item.item
		var quantity = cart_item.quantity
		
		# Update shop inventory
		if item.quantity > 0:
			item.quantity -= quantity
		
		purchased_items.append(cart_item)
		emit_signal("item_purchased", item, quantity)
	
	emit_signal("transaction_completed", purchased_items, cart_total)
	
	# Clear cart
	cart_items.clear()
	cart_panel.hide()
	
	_update_gold_display()
	_update_display()
	_show_message("Purchase complete! Total: %dg" % cart_total)

func _on_clear_cart_pressed():
	cart_items.clear()
	_update_cart_display()
	cart_panel.hide()

func _on_search_changed(text: String):
	_update_display()

func _on_filter_changed(index: int):
	_update_display()

func _update_gold_display():
	player_gold_label.text = "Gold: %d" % player_gold

func _show_message(text: String):
	var notification = Label.new()
	notification.text = text
	notification.rect_position = Vector2(rect_size.x / 2 - 150, 100)
	notification.rect_min_size = Vector2(300, 50)
	add_child(notification)
	
	var tween = Tween.new()
	add_child(tween)
	
	tween.interpolate_property(notification, "modulate:a", 1.0, 0.0, 2.0,
		Tween.TRANS_LINEAR, Tween.EASE_IN, 1.0)
	tween.start()
	
	yield(tween, "tween_all_completed")
	notification.queue_free()
	tween.queue_free()

func set_player_gold(amount: int):
	player_gold = amount
	_update_gold_display()

func set_player_inventory(inventory: Array):
	player_inventory = inventory
	if selected_tab == "sell":
		_update_display()

func add_shop_item(item: ShopItem):
	shop_inventory.append(item)
	if selected_tab == "buy":
		_update_display()

func close_shop():
	emit_signal("shop_closed")