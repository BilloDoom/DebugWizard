extends Control

const REGISTRY_PATH = "res://addons/debugWizard/signal_registry.cfg"

enum SignalType { LABEL, LINE, STEP }

var registry: Dictionary = {}
var signal_connections: Dictionary = {}  # Tracks connected signals
var _current_scene: Node = null
var _cleanup_scheduled: bool = false

@onready var parent: VBoxContainer = $PanelContainer/MarginContainer/VBoxContainer
@export var debug_graph: PackedScene


func _ready() -> void:
	for child in parent.get_children():
		registry[child.name] = child
	
	# Wait for scene tree to be ready, then connect registered signals
	get_tree().process_frame.connect(_on_first_frame, CONNECT_ONE_SHOT)


func _process(_delta: float) -> void:
	# Check for scene change
	var current = get_tree().current_scene
	if current != _current_scene:
		_current_scene = current
		_on_scene_changed()


func _on_first_frame() -> void:
	_load_and_connect_signals()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_debug"):
		visible = !visible


func _load_and_connect_signals() -> void:
	var config = ConfigFile.new()
	var err = config.load(REGISTRY_PATH)
	
	if err != OK:
		return
	
	for section in config.get_sections():
		var node_path = config.get_value(section, "node_path", "")
		var signal_name = config.get_value(section, "signal_name", "")
		var display_name = config.get_value(section, "display_name", "")
		var sig_type = config.get_value(section, "type", SignalType.LABEL)
		var color = config.get_value(section, "color", Color.WHITE)
		
		_connect_signal(node_path, signal_name, display_name, sig_type, color)


func _connect_signal(node_path: String, signal_name: String, display_name: String, sig_type: int, color: Color) -> void:
	var node = get_node_or_null(node_path)
	if not node:
		# Try to find it when scene is fully loaded
		call_deferred("_deferred_connect_signal", node_path, signal_name, display_name, sig_type, color)
		return
	
	_do_connect(node, node_path, signal_name, display_name, sig_type, color)


func _deferred_connect_signal(node_path: String, signal_name: String, display_name: String, sig_type: int, color: Color) -> void:
	# Wait a bit for scene to load
	await get_tree().create_timer(0.1).timeout
	
	var node = get_node_or_null(node_path)
	if not node:
		push_warning("DebugWizard: Could not find node at path '%s'" % node_path)
		return
	
	_do_connect(node, node_path, signal_name, display_name, sig_type, color)


func _do_connect(node: Node, node_path: String, signal_name: String, display_name: String, sig_type: int, color: Color) -> void:
	if not node.has_signal(signal_name):
		push_warning("DebugWizard: Node '%s' does not have signal '%s'" % [node_path, signal_name])
		return
	
	var unique_id = "%s::%s" % [node_path, signal_name]
	
	# Prevent duplicate connections
	if signal_connections.has(unique_id):
		return
	
	# Setup display based on type
	match sig_type:
		SignalType.LABEL:
			create_label(display_name, "signals")
			var callable = _on_label_signal.bind(display_name)
			node.connect(signal_name, callable)
			signal_connections[unique_id] = { "node": node, "signal": signal_name, "callable": callable, "display_name": display_name, "type": sig_type }
		
		SignalType.LINE:
			if not registry.has("signal_graph"):
				create_graph("signal_graph", "signals")
			register_line("signal_graph", display_name, color, 0.0, 100.0)
			var callable = _on_line_signal.bind(display_name)
			node.connect(signal_name, callable)
			signal_connections[unique_id] = { "node": node, "signal": signal_name, "callable": callable, "display_name": display_name, "type": sig_type }
		
		SignalType.STEP:
			if not registry.has("signal_graph"):
				create_graph("signal_graph", "signals")
			register_step("signal_graph", display_name, color)
			var callable = _on_step_signal.bind(display_name)
			node.connect(signal_name, callable)
			signal_connections[unique_id] = { "node": node, "signal": signal_name, "callable": callable, "display_name": display_name, "type": sig_type }
	
	print("DebugWizard: Connected to signal '%s' on '%s'" % [signal_name, node_path])


func _on_label_signal(value, display_name: String) -> void:
	var formatted_value = value
	if typeof(value) == TYPE_FLOAT:
		formatted_value = "%.2f" % value
	send_args(display_name, { display_name: formatted_value })


func _on_line_signal(value: float, display_name: String) -> void:
	send_args("signal_graph", { display_name: value })


func _on_step_signal(triggered: bool, display_name: String) -> void:
	send_args("signal_graph", { display_name: triggered })


func disconnect_all_signals() -> void:
	for unique_id in signal_connections.keys():
		var data = signal_connections[unique_id]
		if is_instance_valid(data.node):
			data.node.disconnect(data.signal, data.callable)
	signal_connections.clear()


func _on_scene_changed() -> void:
	# Defer cleanup to ensure scene is fully loaded
	call_deferred("_cleanup_invalid_entries")


func _cleanup_invalid_entries() -> void:
	# Clean up signal connections for nodes that no longer exist
	var signals_to_remove: Array = []
	
	for unique_id in signal_connections.keys():
		var data = signal_connections[unique_id]
		if not is_instance_valid(data.node):
			signals_to_remove.append(unique_id)
	
	for unique_id in signals_to_remove:
		var data = signal_connections[unique_id]
		var display_name = data.get("display_name", "")
		var sig_type = data.get("type", -1)
		
		signal_connections.erase(unique_id)
		
		# Remove UI element based on type
		if sig_type == SignalType.LABEL:
			_remove_registry_entry(display_name)
		elif sig_type in [SignalType.LINE, SignalType.STEP]:
			if registry.has("signal_graph"):
				var graph_node = registry["signal_graph"]["node"]
				if sig_type == SignalType.LINE:
					graph_node.graph.lines.erase(display_name)
				else:
					graph_node.graph.steps.erase(display_name)
				graph_node.remove_legend(display_name)
				
				if graph_node.graph.lines.is_empty() and graph_node.graph.steps.is_empty():
					_remove_registry_entry("signal_graph")
	
	# Clean up registry entries (function-registered) that have invalid nodes
	var registry_to_remove: Array = []
	
	for entry_name in registry.keys():
		var entry = registry[entry_name]
		# Check if this entry has an associated owner node that's no longer valid
		if entry.has("owner") and not is_instance_valid(entry["owner"]):
			registry_to_remove.append(entry_name)
	
	for entry_name in registry_to_remove:
		_remove_registry_entry(entry_name)
	
	# Try to reconnect signals for the new scene
	_load_and_connect_signals()


func _remove_registry_entry(entry_name: String) -> void:
	if not registry.has(entry_name):
		return
	
	var entry = registry[entry_name]
	var node = entry["node"]
	
	if is_instance_valid(node):
		node.queue_free()
	
	registry.erase(entry_name)


func create_graph(graph_name: String, group: String = "default", owner_node: Node = null) -> void:
	if registry.has(graph_name):
		push_warning("graph " + graph_name + " already exists")
		return
	var g = debug_graph.instantiate()
	g.name = graph_name
	parent.add_child(g)
	
	# If no owner specified, try to get the caller's node
	if owner_node == null:
		owner_node = _get_caller_node()
	
	registry[graph_name] = {"node" = g, "type" = "graph", "group" = group, "owner" = owner_node}


func register_line(prop_name: String, id: String, color: Color, d_min: float, d_max: float, amplitude: float = 1.0) -> void:
	if registry.has(prop_name) and registry[prop_name]["type"] == "graph":
		registry[prop_name]["node"].populate_legend(id, color)
		registry[prop_name]["node"].graph.add_line(id, color, d_min, d_max, amplitude)


func register_step(graph_name: String, id: String, color: Color) -> void:
	if registry.has(graph_name) and registry[graph_name]["type"] == "graph":
		registry[graph_name]["node"].populate_legend(id, color)
		registry[graph_name]["node"].graph.add_step(id, color)


func create_label(lbl_name: String, group: String = "default", owner_node: Node = null) -> void:
	if registry.has(lbl_name):
		push_warning("label " + lbl_name + " already exists")
		return
	var l = Label.new()
	l.name = lbl_name
	parent.add_child(l)
	
	# If no owner specified, try to get the caller's node
	if owner_node == null:
		owner_node = _get_caller_node()
	
	registry[lbl_name] = {"node" = l, "type" = "label", "group" = group, "owner" = owner_node}


func _get_caller_node() -> Node:
	# Try to find the scene root as a fallback owner
	var root = get_tree().current_scene
	return root


func send_args(prop_name: String, args: Dictionary = {}) -> void:
	if not registry.has(prop_name):
		return
	
	var entry = registry[prop_name]
	var node = entry["node"]

	if entry["type"] == "label":
		var text := []
		for key in args.keys():
			text.append("%s=%s" % [key, str(args[key])])
		node.text = ", \t".join(text)
	
	if entry["type"] == "graph":
		for key in args.keys():
			var value = args[key]
			if typeof(value) in [TYPE_FLOAT, TYPE_INT]:
				node.graph.add_line_value(key, float(value))
			elif typeof(value) == TYPE_BOOL:
				node.graph.add_step_value(key, value)
