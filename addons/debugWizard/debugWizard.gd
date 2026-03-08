@tool
extends EditorPlugin

const REGISTRY_NAME = "DebugRegistry"
const REGISTRY_PATH = "res://addons/debugWizard/debug_registry.gd"
const UI_NAME = "DebugWizard"
const UI_PATH = "res://addons/debugWizard/debug_ui.tscn"
const DATA_DIR = "res://addons/debugWizard/data/"

var dock


func _enable_plugin() -> void:
	_ensure_data_dir_exists()
	# Registry must be added first (DebugUi depends on it)
	add_autoload_singleton(REGISTRY_NAME, REGISTRY_PATH)
	add_autoload_singleton(UI_NAME, UI_PATH)


func _disable_plugin() -> void:
	_ensure_data_dir_exists()
	remove_autoload_singleton(UI_NAME)
	remove_autoload_singleton(REGISTRY_NAME)


func _ensure_data_dir_exists() -> void:
	if not DirAccess.dir_exists_absolute(DATA_DIR):
		DirAccess.make_dir_recursive_absolute(DATA_DIR)
		print("DebugWizard: Created data directory at %s" % DATA_DIR)


func _enter_tree() -> void:
	# Load the dock scene and instantiate it
	dock = preload("res://addons/debugWizard/debug_dock.tscn").instantiate()
	
	# Add the loaded scene to the docks (right side, upper-right where Inspector/Node/History are)
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, dock)


func _exit_tree() -> void:
	# Remove the dock
	remove_control_from_docks(dock)
	# Erase the control from memory
	dock.free()
