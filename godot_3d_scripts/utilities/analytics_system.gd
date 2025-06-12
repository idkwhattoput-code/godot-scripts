extends Node

signal event_tracked(event_name, properties)
signal session_started(session_id)
signal session_ended(session_id, duration)

var analytics_enabled = true
var session_id = ""
var session_start_time = 0
var event_queue = []
var user_properties = {}

var analytics_config = {
	"api_endpoint": "https://api.gameanalytics.com/v2",
	"batch_size": 50,
	"flush_interval": 30.0,
	"max_queue_size": 1000,
	"track_performance": true,
	"track_errors": true,
	"privacy_mode": false
}

var tracked_metrics = {
	"gameplay": {},
	"performance": {},
	"monetization": {},
	"user_behavior": {},
	"technical": {}
}

func _ready():
	set_process(true)
	_start_session()
	_load_user_properties()

func _start_session():
	session_id = _generate_session_id()
	session_start_time = OS.get_ticks_msec()
	
	track_event("session_start", {
		"device": OS.get_name(),
		"os_version": OS.get_version(),
		"game_version": ProjectSettings.get_setting("application/config/version", "1.0"),
		"screen_size": OS.get_screen_size()
	})
	
	emit_signal("session_started", session_id)

func track_event(event_name, properties = {}):
	if not analytics_enabled:
		return
	
	if analytics_config.privacy_mode and _is_sensitive_event(event_name):
		return
	
	var event_data = {
		"event": event_name,
		"properties": properties,
		"timestamp": OS.get_unix_time(),
		"session_id": session_id,
		"user_id": _get_user_id()
	}
	
	event_queue.append(event_data)
	emit_signal("event_tracked", event_name, properties)
	
	if event_queue.size() >= analytics_config.batch_size:
		_flush_events()

func track_screen_view(screen_name, properties = {}):
	properties["screen_name"] = screen_name
	track_event("screen_view", properties)

func track_player_action(action, context = {}):
	var properties = {
		"action": action,
		"context": context,
		"player_level": _get_player_level(),
		"play_time": _get_play_time()
	}
	
	track_event("player_action", properties)

func track_game_economy(event_type, currency, amount, item = null):
	var properties = {
		"event_type": event_type,
		"currency": currency,
		"amount": amount,
		"balance_after": _get_currency_balance(currency)
	}
	
	if item:
		properties["item"] = item
	
	track_event("economy_event", properties)
	_update_metric("monetization", currency + "_flow", amount)

func track_progression(milestone_type, milestone_id, properties = {}):
	properties["milestone_type"] = milestone_type
	properties["milestone_id"] = milestone_id
	properties["time_to_complete"] = _get_time_since_last_milestone()
	
	track_event("progression", properties)
	_update_metric("gameplay", "milestones_completed", 1)

func track_performance_metric(metric_name, value):
	if not analytics_config.track_performance:
		return
	
	var properties = {
		"metric": metric_name,
		"value": value,
		"fps": Engine.get_frames_per_second(),
		"memory_usage": OS.get_static_memory_usage()
	}
	
	track_event("performance", properties)
	_update_metric("performance", metric_name, value)

func track_error(error_type, error_message, stack_trace = ""):
	if not analytics_config.track_errors:
		return
	
	var properties = {
		"error_type": error_type,
		"error_message": error_message,
		"stack_trace": stack_trace,
		"scene": get_tree().current_scene.name if get_tree().current_scene else "unknown"
	}
	
	track_event("error", properties)
	_update_metric("technical", "errors_" + error_type, 1)

func track_custom_metric(category, metric_name, value):
	_update_metric(category, metric_name, value)
	
	track_event("custom_metric", {
		"category": category,
		"metric": metric_name,
		"value": value
	})

func set_user_property(key, value):
	user_properties[key] = value
	_save_user_properties()

func increment_user_property(key, amount = 1):
	if user_properties.has(key) and typeof(user_properties[key]) == TYPE_INT:
		user_properties[key] += amount
	else:
		user_properties[key] = amount
	
	_save_user_properties()

func track_revenue(amount, currency, product_id = null):
	var properties = {
		"amount": amount,
		"currency": currency,
		"lifetime_value": _get_lifetime_value() + amount
	}
	
	if product_id:
		properties["product_id"] = product_id
	
	track_event("revenue", properties)
	increment_user_property("lifetime_value", amount)

func track_ad_event(ad_type, event_type, placement = null):
	var properties = {
		"ad_type": ad_type,
		"event_type": event_type,
		"session_ad_count": _get_session_ad_count()
	}
	
	if placement:
		properties["placement"] = placement
	
	track_event("ad_event", properties)

func start_timed_event(event_name):
	var timer_key = "timer_" + event_name
	set_meta(timer_key, OS.get_ticks_msec())

func end_timed_event(event_name, properties = {}):
	var timer_key = "timer_" + event_name
	if not has_meta(timer_key):
		return
	
	var start_time = get_meta(timer_key)
	var duration = OS.get_ticks_msec() - start_time
	
	properties["duration_ms"] = duration
	track_event(event_name, properties)
	
	remove_meta(timer_key)

func _process(delta):
	_flush_events_periodically()

var flush_timer = 0.0
func _flush_events_periodically():
	flush_timer += get_process_delta_time()
	
	if flush_timer >= analytics_config.flush_interval:
		flush_timer = 0.0
		_flush_events()

func _flush_events():
	if event_queue.size() == 0:
		return
	
	var events_to_send = []
	var count = min(event_queue.size(), analytics_config.batch_size)
	
	for i in range(count):
		events_to_send.append(event_queue[i])
	
	event_queue = event_queue.slice(count, event_queue.size())
	
	_send_events(events_to_send)

func _send_events(events):
	pass

func _update_metric(category, metric_name, value):
	if not tracked_metrics.has(category):
		tracked_metrics[category] = {}
	
	if not tracked_metrics[category].has(metric_name):
		tracked_metrics[category][metric_name] = {
			"total": 0,
			"count": 0,
			"min": value,
			"max": value
		}
	
	var metric = tracked_metrics[category][metric_name]
	metric.total += value
	metric.count += 1
	metric.min = min(metric.min, value)
	metric.max = max(metric.max, value)

func get_metric_summary(category, metric_name):
	if not tracked_metrics.has(category):
		return null
	
	if not tracked_metrics[category].has(metric_name):
		return null
	
	var metric = tracked_metrics[category][metric_name]
	return {
		"average": metric.total / float(metric.count) if metric.count > 0 else 0,
		"total": metric.total,
		"count": metric.count,
		"min": metric.min,
		"max": metric.max
	}

func _generate_session_id():
	return str(OS.get_unix_time()) + "_" + str(randi() % 10000)

func _get_user_id():
	if not user_properties.has("user_id"):
		user_properties["user_id"] = OS.get_unique_id()
	return user_properties["user_id"]

func _get_player_level():
	return user_properties.get("player_level", 1)

func _get_play_time():
	return (OS.get_ticks_msec() - session_start_time) / 1000.0

func _get_currency_balance(currency):
	return 0

func _get_time_since_last_milestone():
	return 0

func _get_lifetime_value():
	return user_properties.get("lifetime_value", 0)

func _get_session_ad_count():
	return tracked_metrics.get("monetization", {}).get("ads_shown", {}).get("count", 0)

func _is_sensitive_event(event_name):
	var sensitive_events = ["payment", "personal_info", "location"]
	return event_name in sensitive_events

func _save_user_properties():
	var file = File.new()
	if file.open("user://analytics_user.dat", File.WRITE) == OK:
		file.store_var(user_properties)
		file.close()

func _load_user_properties():
	var file = File.new()
	if file.file_exists("user://analytics_user.dat"):
		if file.open("user://analytics_user.dat", File.READ) == OK:
			user_properties = file.get_var()
			file.close()

func set_analytics_enabled(enabled):
	analytics_enabled = enabled

func set_privacy_mode(enabled):
	analytics_config.privacy_mode = enabled

func export_analytics_data():
	return {
		"session_id": session_id,
		"duration": (OS.get_ticks_msec() - session_start_time) / 1000.0,
		"events_tracked": event_queue.size(),
		"metrics": tracked_metrics,
		"user_properties": user_properties
	}

func _exit_tree():
	track_event("session_end", {
		"duration": (OS.get_ticks_msec() - session_start_time) / 1000.0
	})
	
	_flush_events()
	emit_signal("session_ended", session_id, OS.get_ticks_msec() - session_start_time)