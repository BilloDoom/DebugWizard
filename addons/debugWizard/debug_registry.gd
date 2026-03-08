extends Node
class_name DebugRegistryClass

## DebugRegistry - Central hub for debug data
## Game scripts call watch/unwatch/dispatch here
## DebugUi reads from here each frame

const REGISTRY_PATH = "res://addons/debugWizard/signal_registry.cfg"

enum DisplayType { LABEL = 0, LINE = 1, _STEP = 2 }

signal event_dispatched(category: String, data: Dictionary)
signal scene_changed(removed_watches: Array, removed_signals: Array)

var _watched: Dictionary = {}
var _signal_connections: Dictionary = {}
var _config_entries: Array = []
var _current_scene: Node = null


func _ready() -> void:
	_load_config()
	get_tree().process_frame.connect(_on_first_frame, CONNECT_ONE_SHOT)


func _process(_delta: float) -> void:
	var current = get_tree().current_scene
	if current != _current_scene:
		_current_scene = current
		if current != null:
			call_deferred("_resolve_connections")


func _on_first_frame() -> void:
	_current_scene = get_tree().current_scene
	_resolve_connections()


# =============================================================================
# PUBLIC API - Watch / Unwatch
# =============================================================================

func watch(label: String, getter: Callable, type: DisplayType = DisplayType.LABEL, color: Color = Color.WHITE) -> void:
	var owner = get_tree().current_scene
	_watched[label] = {
		"getter": getter,
		"type": type,
		"color": color,
		"owner": owner
	}
	# Clean up this label automatically when the owning scene exits
	if owner and not owner.tree_exiting.is_connected(_on_owner_exiting.bind(owner)):
		owner.tree_exiting.connect(_on_owner_exiting.bind(owner), CONNECT_ONE_SHOT)


func watch_node(label: String, node: Node, property: String, type: DisplayType = DisplayType.LABEL, color: Color = Color.WHITE) -> void:
	_watched[label] = {
		"getter": func(): return node.get_indexed(property),
		"type": type,
		"color": color,
		"owner": node
	}
	if node and not node.tree_exiting.is_connected(_on_owner_exiting.bind(node)):
		node.tree_exiting.connect(_on_owner_exiting.bind(node), CONNECT_ONE_SHOT)


func unwatch(label: String) -> void:
	_watched.erase(label)


func unwatch_owner(owner: Node) -> void:
	var to_remove: Array = []
	for label in _watched.keys():
		if _watched[label].get("owner") == owner:
			to_remove.append(label)
	for label in to_remove:
		_watched.erase(label)


# =============================================================================
# PUBLIC API - Dispatch
# =============================================================================

func dispatch(category: String, data: Dictionary) -> void:
	event_dispatched.emit(category, data)


# =============================================================================
# PUBLIC API - Read (called by DebugUi)
# =============================================================================

func get_watched() -> Dictionary:
	var result: Dictionary = {}
	for label in _watched.keys():
		var entry = _watched[label]
		var owner = entry.get("owner")
		if owner != null and not is_instance_valid(owner):
			continue
		if entry["getter"].is_valid():
			result[label] = {
				"value": entry["getter"].call(),
				"type": entry["type"],
				"color": entry["color"]
			}
	return result


func get_signal_connections() -> Dictionary:
	return _signal_connections


# =============================================================================
# OWNER EXIT HANDLER
# =============================================================================

func _on_owner_exiting(owner: Node) -> void:
	# Collect and remove watched values owned by this node/scene
	var removed_watches: Array = []
	var to_remove: Array = []

	for label in _watched.keys():
		if _watched[label].get("owner") == owner:
			to_remove.append(label)
			removed_watches.append({ "name": label, "type": _watched[label]["type"] })

	for label in to_remove:
		_watched.erase(label)

	# Collect and remove signal connections whose node is owned by this scene
	var removed_signals: Array = []
	var signals_to_remove: Array = []

	for unique_id in _signal_connections.keys():
		var data = _signal_connections[unique_id]
		# Node is either the owner itself or a child of it
		if data["node"] == owner or (is_instance_valid(data["node"]) and owner.is_ancestor_of(data["node"])):
			signals_to_remove.append(unique_id)
			removed_signals.append({ "name": data["display_name"], "type": data["type"] })

	for unique_id in signals_to_remove:
		_signal_connections.erase(unique_id)

	scene_changed.emit(removed_watches, removed_signals)


# =============================================================================
# CONFIG & SIGNAL RESOLUTION
# =============================================================================

func _load_config() -> void:
	_config_entries.clear()
	var config = ConfigFile.new()
	if config.load(REGISTRY_PATH) != OK:
		return
	for section in config.get_sections():
		_config_entries.append({
			"node_path": config.get_value(section, "node_path", ""),
			"signal_name": config.get_value(section, "signal_name", ""),
			"display_name": config.get_value(section, "display_name", ""),
			"type": config.get_value(section, "type", DisplayType.LABEL),
			"color": config.get_value(section, "color", Color.WHITE)
		})


func _resolve_connections() -> void:
	for entry in _config_entries:
		var node_path: String = entry["node_path"]
		var signal_name: String = entry["signal_name"]
		var unique_id = "%s::%s" % [node_path, signal_name]

		if _signal_connections.has(unique_id):
			if is_instance_valid(_signal_connections[unique_id]["node"]):
				continue

		var node = get_node_or_null(node_path)
		if not node:
			continue

		if not node.has_signal(signal_name):
			push_warning("DebugRegistry: Node '%s' has no signal '%s'" % [node_path, signal_name])
			continue

		var sig_type: int = entry["type"]
		var display_name: String = entry["display_name"]
		var callable: Callable

		match sig_type:
			DisplayType.LABEL:
				callable = _on_signal_label.bind(display_name)
			DisplayType.LINE:
				callable = _on_signal_line.bind(display_name)
			DisplayType._STEP:
				callable = _on_signal_step.bind(display_name)

		node.connect(signal_name, callable)

		_signal_connections[unique_id] = {
			"node": node,
			"signal_name": signal_name,
			"callable": callable,
			"display_name": display_name,
			"type": sig_type,
			"color": entry["color"]
		}

		print("DebugRegistry: Connected '%s' on '%s'" % [signal_name, node_path])


# =============================================================================
# SIGNAL HANDLERS
# =============================================================================

func _on_signal_label(value, display_name: String) -> void:
	var formatted = value
	if typeof(value) == TYPE_FLOAT:
		formatted = "%.2f" % value
	dispatch(display_name, { display_name: formatted, "_type": DisplayType.LABEL })


func _on_signal_line(value: float, display_name: String) -> void:
	dispatch(display_name, { "value": value, "_type": DisplayType.LINE })


func _on_signal_step(triggered: bool, display_name: String) -> void:
	dispatch(display_name, { "triggered": triggered, "_type": DisplayType._STEP })
