extends Control

const REGISTRY_PATH = "res://addons/debugWizard/signal_registry.cfg"

enum SignalType { LABEL, LINE, STEP }

var registry: Dictionary = {}
var signal_connections: Dictionary = {}  # Tracks connected signals

@onready var parent: VBoxContainer = $PanelContainer/MarginContainer/VBoxContainer
@export var debug_graph: PackedScene


func _ready() -> void:
	for child in parent.get_children():
		registry[child.name] = child
	
	# Wait for scene tree to be ready, then connect registered signals
	get_tree().process_frame.connect(_on_first_frame, CONNECT_ONE_SHOT)


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
			signal_connections[unique_id] = { "node": node, "signal": signal_name, "callable": callable }
		
		SignalType.LINE:
			if not registry.has("signal_graph"):
				create_graph("signal_graph", "signals")
			register_line("signal_graph", display_name, color, 0.0, 100.0)
			var callable = _on_line_signal.bind(display_name)
			node.connect(signal_name, callable)
			signal_connections[unique_id] = { "node": node, "signal": signal_name, "callable": callable }
		
		SignalType.STEP:
			if not registry.has("signal_graph"):
				create_graph("signal_graph", "signals")
			register_step("signal_graph", display_name, color)
			var callable = _on_step_signal.bind(display_name)
			node.connect(signal_name, callable)
			signal_connections[unique_id] = { "node": node, "signal": signal_name, "callable": callable }
	
	print("DebugWizard: Connected to signal '%s' on '%s'" % [signal_name, node_path])


func _on_label_signal(value, display_name: String) -> void:
	send_args(display_name, { "value": value })


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


func create_graph(graph_name: String, group: String = "default") -> void:
	if registry.has(graph_name):
		push_warning("graph " + graph_name + " already exists")
		return
	var g = debug_graph.instantiate()
	g.name = graph_name
	parent.add_child(g)
	
	registry[graph_name] = {"node" = g, "type" = "graph" , "group" = group}


func register_line(prop_name: String, id: String, color: Color, d_min: float, d_max: float, amplitude: float = 1.0) -> void:
	if registry.has(prop_name) and registry[prop_name]["type"] == "graph":
		registry[prop_name]["node"].populate_legend(id, color)
		registry[prop_name]["node"].graph.add_line(id, color, d_min, d_max, amplitude)


func register_step(graph_name: String, id: String, color: Color) -> void:
	if registry.has(graph_name) and registry[graph_name]["type"] == "graph":
		registry[graph_name]["node"].populate_legend(id, color)
		registry[graph_name]["node"].graph.add_step(id, color)


func create_label(lbl_name: String, group: String = "default") -> void:
	if registry.has(lbl_name):
		push_warning("label " + lbl_name + " already exists")
		return
	var l = Label.new()
	l.name = lbl_name
	parent.add_child(l)
	
	registry[lbl_name] = {"node" = l, "type" = "label" ,"group" = group}


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
