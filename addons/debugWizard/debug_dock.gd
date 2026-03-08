@tool
extends Control

const DATA_DIR = "res://addons/debugWizard/data/"
const SAVE_PATH = DATA_DIR + "signal_registry.cfg"

# Signal tree (for adding new signals from selected node)
@onready var signal_tree: Tree = $VBoxContainer/SignalTree
@onready var selected_node_label: Label = $VBoxContainer/SelectedNodeLabel

# Registered signals tree (clickable list)
@onready var registered_tree: Tree = $VBoxContainer/RegisteredTree

# Edit section (disabled when no signal selected)
@onready var edit_section: VBoxContainer = $VBoxContainer/EditSection
@onready var display_name_edit: LineEdit = $VBoxContainer/EditSection/DisplayNameContainer/DisplayNameEdit
@onready var type_option: OptionButton = $VBoxContainer/EditSection/TypeContainer/TypeOption
@onready var color_picker: ColorPickerButton = $VBoxContainer/EditSection/ColorContainer/ColorPicker

var registered_signals: Dictionary = {}
var _selected_node: Node = null
var _selected_signal_id: String = ""
var _signal_icon: Texture2D
var _remove_icon: Texture2D

enum SignalType { LABEL, LINE, _STEP }


func _ready() -> void:
	if not Engine.is_editor_hint():
		return
	
	# Setup type dropdown
	type_option.clear()
	type_option.add_item("Label", SignalType.LABEL)
	type_option.add_item("Line (Graph)", SignalType.LINE)
	# Step is hidden until functional
	#type_option.add_item("Step (Graph)", SignalType._STEP)
	
	_signal_icon = EditorInterface.get_editor_theme().get_icon("Signal", "EditorIcons")
	_remove_icon = EditorInterface.get_editor_theme().get_icon("Remove", "EditorIcons")
	
	# Setup signal tree (for adding)
	signal_tree.columns = 2
	signal_tree.set_column_expand(0, true)
	signal_tree.set_column_expand(1, false)
	signal_tree.set_column_custom_minimum_width(1, 60)
	signal_tree.hide_root = true
	signal_tree.button_clicked.connect(_on_signal_tree_button_clicked)
	
	# Setup registered tree (for selecting/editing)
	registered_tree.columns = 2
	registered_tree.set_column_expand(0, true)
	registered_tree.set_column_expand(1, false)
	registered_tree.set_column_custom_minimum_width(1, 40)
	registered_tree.hide_root = true
	registered_tree.item_selected.connect(_on_registered_item_selected)
	registered_tree.button_clicked.connect(_on_registered_tree_button_clicked)
	
	# Setup edit section - auto-save on change
	display_name_edit.text_changed.connect(_on_edit_changed)
	type_option.item_selected.connect(_on_edit_changed)
	color_picker.color_changed.connect(_on_edit_changed)
	
	# Connect to editor selection
	var selection = EditorInterface.get_selection()
	if not selection.selection_changed.is_connected(_on_selection_changed):
		selection.selection_changed.connect(_on_selection_changed)
	
	_load_registry()
	_refresh_registered_tree()
	_set_edit_section_enabled(false)


# =============================================================================
# EDITOR NODE SELECTION
# =============================================================================

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


# =============================================================================
# SIGNAL TREE (for adding signals)
# =============================================================================

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


func _on_signal_tree_button_clicked(item: TreeItem, column: int, id: int, mouse_button: int) -> void:
	if mouse_button != MOUSE_BUTTON_LEFT:
		return
	
	var signal_name = item.get_metadata(0)
	var unique_id = item.get_metadata(1)
	
	if registered_signals.has(unique_id):
		_unregister_signal(unique_id)
	else:
		_register_signal(_selected_node, signal_name)


# =============================================================================
# REGISTERED SIGNALS TREE
# =============================================================================

func _refresh_registered_tree() -> void:
	registered_tree.clear()
	var root = registered_tree.create_item()
	
	for unique_id in registered_signals.keys():
		var data = registered_signals[unique_id]
		var item = registered_tree.create_item(root)
		
		var type_str = ["Label", "Line", "Step"][data.type]
		item.set_text(0, "%s [%s] — %s" % [data.display_name, type_str, data.signal_name])
		item.set_metadata(0, unique_id)
		
		# Set custom color indicator
		item.set_custom_color(0, data.color)
		
		# Add X button for removal
		item.add_button(1, _remove_icon, 0, false, "Remove")
	
	# Refresh signal tree to update track/untrack buttons
	if _selected_node and is_instance_valid(_selected_node):
		_populate_signal_tree(_selected_node)
	
	# Disable edit section if selected signal no longer exists
	if not registered_signals.has(_selected_signal_id):
		_selected_signal_id = ""
		_set_edit_section_enabled(false)


func _on_registered_item_selected() -> void:
	var selected_item = registered_tree.get_selected()
	if not selected_item:
		_set_edit_section_enabled(false)
		_selected_signal_id = ""
		return
	
	_selected_signal_id = selected_item.get_metadata(0)
	if not registered_signals.has(_selected_signal_id):
		_set_edit_section_enabled(false)
		return
	
	var data = registered_signals[_selected_signal_id]
	
	# Populate edit fields
	display_name_edit.text = data.display_name
	color_picker.color = data.color
	
	# Set type dropdown
	for i in type_option.item_count:
		if type_option.get_item_id(i) == data.type:
			type_option.select(i)
			break
	
	_set_edit_section_enabled(true)


func _on_registered_tree_button_clicked(item: TreeItem, column: int, id: int, mouse_button: int) -> void:
	if mouse_button != MOUSE_BUTTON_LEFT:
		return
	
	var unique_id = item.get_metadata(0)
	_unregister_signal(unique_id)


# =============================================================================
# REGISTER / UNREGISTER
# =============================================================================

func _register_signal(node: Node, signal_name: String) -> void:
	var runtime_path = _get_runtime_path(node)
	var unique_id = "%s::%s" % [runtime_path, signal_name]
	
	if registered_signals.has(unique_id):
		push_warning("DebugWizard: '%s' already tracked" % unique_id)
		return
	
	# Default values for new signal
	registered_signals[unique_id] = {
		"node_path": runtime_path,
		"signal_name": signal_name,
		"display_name": signal_name,
		"type": SignalType.LABEL,
		"color": Color.WHITE
	}
	
	_save_registry()
	_refresh_registered_tree()
	print("DebugWizard: Registered '%s' on '%s'" % [signal_name, runtime_path])


func _unregister_signal(unique_id: String) -> void:
	if registered_signals.has(unique_id):
		registered_signals.erase(unique_id)
		
		# Clear selection if we just removed the selected signal
		if _selected_signal_id == unique_id:
			_selected_signal_id = ""
			_set_edit_section_enabled(false)
		
		_save_registry()
		_refresh_registered_tree()
		print("DebugWizard: Unregistered '%s'" % unique_id)


# =============================================================================
# EDIT SECTION - Auto-save on change
# =============================================================================

func _set_edit_section_enabled(enabled: bool) -> void:
	display_name_edit.editable = enabled
	type_option.disabled = not enabled
	color_picker.disabled = not enabled
	
	if not enabled:
		display_name_edit.text = ""
		type_option.select(0)
		color_picker.color = Color.WHITE


func _on_edit_changed(_value = null) -> void:
	if _selected_signal_id.is_empty() or not registered_signals.has(_selected_signal_id):
		return
	
	var data = registered_signals[_selected_signal_id]
	
	var new_name = display_name_edit.text.strip_edges()
	if new_name.is_empty():
		new_name = data.signal_name
	
	data.display_name = new_name
	data.type = type_option.get_selected_id()
	data.color = color_picker.color
	
	_save_registry()
	_refresh_registered_tree()


# =============================================================================
# PERSISTENCE
# =============================================================================

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
