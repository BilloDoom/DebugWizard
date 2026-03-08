extends Control

## DebugUi - Visual display for debug data
## Reads from DebugRegistry each frame, never called directly by game scripts

const DisplayType = DebugRegistryClass.DisplayType

@onready var parent: VBoxContainer = $PanelContainer/MarginContainer/VBoxContainer
@export var debug_graph: PackedScene

# Registry entries: { name: { node: Control, type: String, group: String } }
var _registry: Dictionary = {}

# Track which signal displays exist: { display_name: true }
var _signal_displays: Dictionary = {}

var _debug_registry: Node = null


func _ready() -> void:
	_debug_registry = get_node_or_null("/root/DebugRegistry")

	if _debug_registry:
		_debug_registry.event_dispatched.connect(_on_event_dispatched)
		_debug_registry.scene_changed.connect(_on_scene_changed)
		call_deferred("_init_signal_displays")


func _process(_delta: float) -> void:
	if not _debug_registry:
		return

	var watched = _debug_registry.get_watched()

	for label in watched.keys():
		var data = watched[label]
		_update_display(label, data["value"], data["type"], data["color"])


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_debug"):
		visible = !visible


# =============================================================================
# DISPLAY MANAGEMENT
# =============================================================================

func _init_signal_displays() -> void:
	if not _debug_registry:
		return

	var connections = _debug_registry.get_signal_connections()

	for unique_id in connections.keys():
		var data = connections[unique_id]
		_ensure_display_exists(data["display_name"], data["type"], data["color"])
		_signal_displays[data["display_name"]] = true


func _ensure_display_exists(label: String, display_type: int, color: Color) -> void:
	match display_type:
		DisplayType.LABEL:
			if not _registry.has(label):
				_create_label(label, color)
		DisplayType.LINE:
			if not _registry.has("signal_graph"):
				_create_graph("signal_graph")
			_register_line("signal_graph", label, color)
		DisplayType._STEP:
			if not _registry.has("signal_graph"):
				_create_graph("signal_graph")
			__register_step("signal_graph", label, color)


func _update_display(label: String, value, display_type: int, color: Color) -> void:
	_ensure_display_exists(label, display_type, color)

	match display_type:
		DisplayType.LABEL: _update_label(label, value)
		DisplayType.LINE: _update_line(label, value)
		DisplayType._STEP: __update_step(label, value)


func _update_label(label: String, value) -> void:
	if not _registry.has(label):
		return

	var entry = _registry[label]
	if entry["type"] != "label":
		return

	var formatted = value
	if typeof(value) == TYPE_FLOAT:
		formatted = "%.2f" % value

	entry["node"].text = "%s: %s" % [label, str(formatted)]


func _update_line(label: String, value) -> void:
	if not _registry.has("signal_graph"):
		return

	var graph_entry = _registry["signal_graph"]
	if graph_entry["type"] != "graph":
		return

	if typeof(value) in [TYPE_FLOAT, TYPE_INT]:
		graph_entry["node"].graph.add_line_value(label, float(value))


func __update_step(label: String, value) -> void:
	if not _registry.has("signal_graph"):
		return

	var graph_entry = _registry["signal_graph"]
	if graph_entry["type"] != "graph":
		return

	var triggered: bool = false
	if typeof(value) == TYPE_BOOL:
		triggered = value
	elif value:
		triggered = true

	graph_entry["node"].graph.add_step_value(label, triggered)


# =============================================================================
# EVENT HANDLER
# =============================================================================

func _on_event_dispatched(category: String, data: Dictionary) -> void:
	var display_type: int = data.get("_type", DisplayType.LABEL)
	var color: Color = data.get("color", Color.WHITE)

	match display_type:
		DisplayType.LABEL:
			_ensure_display_exists(category, DisplayType.LABEL, color)
			if _registry.has(category) and _registry[category]["type"] == "label":
				var text_parts: Array = []
				for key in data.keys():
					if key.begins_with("_") or key == "color":
						continue
					var val = data[key]
					if typeof(val) == TYPE_FLOAT:
						val = "%.2f" % val
					text_parts.append("%s=%s" % [key, str(val)])
				_registry[category]["node"].text = ", ".join(text_parts)

		DisplayType.LINE:
			_ensure_display_exists(category, DisplayType.LINE, color)
			_update_line(category, data.get("value", 0.0))

		DisplayType._STEP:
			_ensure_display_exists(category, DisplayType._STEP, color)
			__update_step(category, data.get("triggered", true))


# =============================================================================
# CREATE UI ELEMENTS
# =============================================================================

func _create_label(lbl_name: String, color: Color = Color.WHITE, group: String = "default") -> void:
	if _registry.has(lbl_name):
		return

	var l = Label.new()
	l.name = lbl_name
	l.text = lbl_name + ": --"
	l.add_theme_color_override("font_color", color)
	parent.add_child(l)

	_registry[lbl_name] = { "node": l, "type": "label", "group": group, "color": color }


func _create_graph(graph_name: String, group: String = "default") -> void:
	if _registry.has(graph_name):
		return

	var g = debug_graph.instantiate()
	g.name = graph_name
	parent.add_child(g)

	_registry[graph_name] = { "node": g, "type": "graph", "group": group }


func _register_line(graph_name: String, id: String, color: Color, d_min: float = 0.0, d_max: float = 100.0, amplitude: float = 1.0) -> void:
	if not _registry.has(graph_name):
		return

	var entry = _registry[graph_name]
	if entry["type"] != "graph":
		return

	var graph_node = entry["node"]
	if graph_node.graph.lines.has(id):
		return

	graph_node.populate_legend(id, color)
	graph_node.graph.add_line(id, color, d_min, d_max, amplitude)


func __register_step(graph_name: String, id: String, color: Color) -> void:
	if not _registry.has(graph_name):
		return

	var entry = _registry[graph_name]
	if entry["type"] != "graph":
		return

	var graph_node = entry["node"]
	if graph_node.graph.steps.has(id):
		return

	graph_node.populate_legend(id, color)
	graph_node.graph.add_step(id, color)


# =============================================================================
# SCENE CHANGE HANDLER
# =============================================================================

func _on_scene_changed(removed_watches: Array, removed_signals: Array) -> void:
	for info in removed_watches:
		_remove_by_type(info["name"], info["type"])

	for info in removed_signals:
		_remove_by_type(info["name"], info["type"])
		_signal_displays.erase(info["name"])

	# Clean up any registry entries whose nodes have become invalid
	var to_remove: Array = []
	for entry_name in _registry.keys():
		if not is_instance_valid(_registry[entry_name]["node"]):
			to_remove.append(entry_name)
	for entry_name in to_remove:
		_registry.erase(entry_name)

	call_deferred("_init_signal_displays")


func _remove_by_type(name: String, display_type: int) -> void:
	match display_type:
		DisplayType.LABEL: _remove_display(name)
		DisplayType.LINE: _remove_line_from_graph("signal_graph", name)
		DisplayType._STEP: __remove_step_from_graph("signal_graph", name)


# =============================================================================
# CLEANUP
# =============================================================================

func _remove_display(display_name: String) -> void:
	if _registry.has(display_name):
		var entry = _registry[display_name]
		if is_instance_valid(entry["node"]):
			entry["node"].queue_free()
		_registry.erase(display_name)

	_signal_displays.erase(display_name)


func _remove_line_from_graph(graph_name: String, line_id: String) -> void:
	if not _registry.has(graph_name):
		return

	var entry = _registry[graph_name]
	if entry["type"] != "graph":
		return

	var graph_node = entry["node"]
	graph_node.graph.lines.erase(line_id)
	graph_node.remove_legend(line_id)

	if graph_node.graph.lines.is_empty() and graph_node.graph.steps.is_empty():
		_remove_display(graph_name)


func __remove_step_from_graph(graph_name: String, step_id: String) -> void:
	if not _registry.has(graph_name):
		return

	var entry = _registry[graph_name]
	if entry["type"] != "graph":
		return

	var graph_node = entry["node"]
	graph_node.graph.steps.erase(step_id)
	graph_node.remove_legend(step_id)

	if graph_node.graph.lines.is_empty() and graph_node.graph.steps.is_empty():
		_remove_display(graph_name)
