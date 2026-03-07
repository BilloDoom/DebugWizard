@tool
extends EditorPlugin

const AUTOLOAD_NAME = "DebugWizard"
const AUTOLOAD_PATH = "res://addons/debugWizard/debug_ui.tscn"

var dock


func _enable_plugin() -> void:
	add_autoload_singleton(AUTOLOAD_NAME, AUTOLOAD_PATH)


func _disable_plugin() -> void:
	remove_autoload_singleton(AUTOLOAD_NAME)


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
