@tool
extends Control

const DATA_DIR = "res://addons/debugWizard/data/"
const SAVE_PATH = DATA_DIR + "signal_registry.cfg"

@onready var display_name_edit: LineEdit = $VBoxContainer/AddSection/DisplayNameEdit
@onready var type_option: OptionButton = $VBoxContainer/AddSection/TypeContainer/TypeOption
@onready var color_picker: ColorPickerButton = $VBoxContainer/AddSection/ColorContainer/ColorPicker
@onready var registered_list: VBoxContainer = $VBoxContainer/ScrollContainer/RegisteredList
@onready var signal_tree: Tree = $VBoxContainer/SignalTree
@onready var selected_node_label: Label = $VBoxContainer/SelectedNodeLabel

var registered_signals: Dictionary = {}
var _selected_node: Node = null
var _signal_icon: Texture2D

enum SignalType { LABEL, LINE, _STEP }


func _ready() -> void:
	if not Engine.is_editor_hint():
		return
	
	type_option.clear()
	type_option.add_item("Label", SignalType.LABEL)
	type_option.add_item("Line (Graph)", SignalType.LINE)
	# Step is hidden until functional
	#type_option.add_item("Step (Graph)", SignalType._STEP)

	_signal_icon = EditorInterface.get_editor_theme().get_icon("Signal", "EditorIcons")

	signal_tree.columns = 2
	signal_tree.set_column_expand(0, true)
	signal_tree.set_column_expand(1, false)
	signal_tree.set_column_custom_minimum_width(1, 60)
	signal_tree.hide_root = true
	signal_tree.button_clicked.connect(_on_tree_button_clicked)

	var selection = EditorInterface.get_selection()
	if not selection.selection_changed.is_connected(_on_selection_changed):
		selection.selection_changed.connect(_on_selection_changed)

	_load_registry()
	_refresh_list()


# --- Selection ---

func _on_selection_changed() -> void:
	var selected = EditorInterface.get_selection().get_selected_nodes()
	if selected.is_empty():
		_selected_node = null
		selected_node_label.text = "No node selected"
		signal_tree.clear()
		return

	_selected_node = selected[0]
	selected_node_label.text = _get_runtime_path(_selected_node)
	_populate_signal_tree(_selected_node)


func _get_runtime_path(node: Node) -> String:
	var scene_root = EditorInterface.get_edited_scene_root()
	if not scene_root:
		return ""
	if node == scene_root:
		return "/root/" + scene_root.name
	var relative_path = scene_root.get_path_to(node)
	return "/root/" + scene_root.name + "/" + str(relative_path)


# --- Signal Tree ---

func _populate_signal_tree(node: Node) -> void:
	signal_tree.clear()
	var root = signal_tree.create_item()

	var grouped: Dictionary = {}  # group_name -> Array of signal dicts

	# Script signals first
	if node.get_script():
		var script = node.get_script()
		var script_signals = script.get_script_signal_list()
		if not script_signals.is_empty():
			var script_name = script.resource_path.get_file().get_basename()
			grouped[script_name] = script_signals

	# Built-in signals grouped by declaring class
	for sig in node.get_signal_list():
		# skip if already in script signals
		var in_script = false
		for group in grouped.values():
			for s in group:
				if s.name == sig.name:
					in_script = true
					break

		if in_script:
			continue

		var declaring_class = _find_declaring_class(sig.name, node)
		if not grouped.has(declaring_class):
			grouped[declaring_class] = []
		grouped[declaring_class].append(sig)

	if grouped.is_empty():
		var item = signal_tree.create_item(root)
		item.set_text(0, "No signals found")
		item.set_selectable(0, false)
		return

	var runtime_path = _get_runtime_path(node)

	for group_name in grouped:
		# Group header
		var header = signal_tree.create_item(root)
		header.set_text(0, group_name)
		header.set_selectable(0, false)
		header.set_selectable(1, false)

		for sig in grouped[group_name]:
			var unique_id = "%s::%s" % [runtime_path, sig.name]
			var already_tracked = registered_signals.has(unique_id)

			var item = signal_tree.create_item(header)
			item.set_icon(0, _signal_icon)
			item.set_text(0, _format_signal(sig))
			item.set_metadata(0, sig.name)
			item.set_metadata(1, unique_id)

			var btn_icon = EditorInterface.get_editor_theme().get_icon(
				"Remove" if already_tracked else "Add", "EditorIcons"
			)
			item.add_button(1, btn_icon, 0, false, "Untrack" if already_tracked else "Track")


func _find_declaring_class(signal_name: String, node: Node) -> String:
	var cls = node.get_class()
	while cls != "":
		var parent = ClassDB.get_parent_class(cls)
		if ClassDB.class_has_signal(cls, signal_name) and not ClassDB.class_has_signal(parent, signal_name):
			return cls
		cls = parent
	return "Unknown"


func _format_signal(sig: Dictionary) -> String:
	var args_str = ""
	if sig.has("args") and sig.args.size() > 0:
		var arg_parts = []
		for arg in sig.args:
			var type_name = _get_type_name(arg.type)
			arg_parts.append("%s: %s" % [arg.name, type_name] if not type_name.is_empty() else arg.name)
		args_str = ", ".join(arg_parts)
	return "%s(%s)" % [sig.name, args_str]


func _get_type_name(type: int) -> String:
	match type:
		TYPE_NIL: return ""
		TYPE_BOOL: return "bool"
		TYPE_INT: return "int"
		TYPE_FLOAT: return "float"
		TYPE_STRING: return "String"
		TYPE_VECTOR2: return "Vector2"
		TYPE_VECTOR3: return "Vector3"
		TYPE_COLOR: return "Color"
		TYPE_OBJECT: return "Object"
		_: return ""


func _on_tree_button_clicked(item: TreeItem, column: int, id: int, mouse_button: int) -> void:
	if mouse_button != MOUSE_BUTTON_LEFT:
		return

	var signal_name = item.get_metadata(0)
	var unique_id = item.get_metadata(1)

	if registered_signals.has(unique_id):
		_on_remove_pressed(unique_id)
	else:
		_register_signal(_selected_node, signal_name)


# --- Register / Remove ---

func _register_signal(node: Node, signal_name: String) -> void:
	var runtime_path = _get_runtime_path(node)
	var unique_id = "%s::%s" % [runtime_path, signal_name]

	if registered_signals.has(unique_id):
		push_warning("DebugWizard: '%s' already tracked" % unique_id)
		return

	var display_name = display_name_edit.text.strip_edges()
	if display_name.is_empty():
		display_name = signal_name

	registered_signals[unique_id] = {
		"node_path": runtime_path,
		"signal_name": signal_name,
		"display_name": display_name,
		"type": type_option.get_selected_id(),
		"color": color_picker.color
	}

	_save_registry()
	_refresh_list()
	print("DebugWizard: Registered '%s' on '%s'" % [signal_name, runtime_path])


func _on_remove_pressed(unique_id: String) -> void:
	if registered_signals.has(unique_id):
		registered_signals.erase(unique_id)
		_save_registry()
		_refresh_list()
		print("DebugWizard: Unregistered '%s'" % unique_id)


# --- Registered List ---

func _refresh_list() -> void:
	for child in registered_list.get_children():
		child.queue_free()

	for unique_id in registered_signals.keys():
		var data = registered_signals[unique_id]
		registered_list.add_child(_create_list_entry(unique_id, data))

	if _selected_node and is_instance_valid(_selected_node):
		_populate_signal_tree(_selected_node)


func _create_list_entry(unique_id: String, data: Dictionary) -> HBoxContainer:
	var container = HBoxContainer.new()

	var color_rect = ColorRect.new()
	color_rect.custom_minimum_size = Vector2(16, 16)
	color_rect.color = data.color
	container.add_child(color_rect)

	var label = Label.new()
	var type_str = ["Label", "Line", "Step"][data.type]
	label.text = "%s [%s] — %s" % [data.display_name, type_str, data.node_path]
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.clip_text = true
	container.add_child(label)

	var remove_btn = Button.new()
	remove_btn.text = "X"
	remove_btn.pressed.connect(_on_remove_pressed.bind(unique_id))
	container.add_child(remove_btn)

	return container


# --- Persistence ---

func _save_registry() -> void:
	var config = ConfigFile.new()

	for unique_id in registered_signals.keys():
		var data = registered_signals[unique_id]
		config.set_value(unique_id, "node_path", data.node_path)
		config.set_value(unique_id, "signal_name", data.signal_name)
		config.set_value(unique_id, "display_name", data.display_name)
		config.set_value(unique_id, "type", data.type)
		config.set_value(unique_id, "color", data.color)

	var err = config.save(SAVE_PATH)
	if err != OK:
		push_error("DebugWizard: Failed to save registry: %s" % err)


func _load_registry() -> void:
	var config = ConfigFile.new()
	var err = config.load(SAVE_PATH)

	if err != OK:
		return

	registered_signals.clear()

	for section in config.get_sections():
		registered_signals[section] = {
			"node_path": config.get_value(section, "node_path", ""),
			"signal_name": config.get_value(section, "signal_name", ""),
			"display_name": config.get_value(section, "display_name", ""),
			"type": config.get_value(section, "type", SignalType.LABEL),
			"color": config.get_value(section, "color", Color.WHITE)
		}


func get_registered_signals() -> Dictionary:
	return registered_signals
