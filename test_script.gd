extends Node

## Test script for DebugWizard system
## Demonstrates graphs, labels, lines, and step triggers

signal health_changed(value: float)

var time_elapsed: float = 0.0
var bounce_value: float = 0.0
var random_value: float = 0.0
var is_jumping: bool = false
var jump_timer: float = 0.0
var health: float = 100.0

func _ready() -> void:
	# Wait a frame for debug_ui to initialize
	await get_tree().process_frame
	
	# Create a label for basic stats
	DebugWizard.create_label("stats", "main")
	
	# Create a graph for sine wave visualization
	DebugWizard.create_graph("wave_graph", "main")
	DebugWizard.register_line("wave_graph", "sine", Color.CYAN, -1.0, 1.0)
	DebugWizard.register_line("wave_graph", "cosine", Color.MAGENTA, -1.0, 1.0)
	
	# Create a graph for random/bounce values
	DebugWizard.create_graph("movement_graph", "main")
	DebugWizard.register_line("movement_graph", "bounce", Color.GREEN, 0.0, 100.0)
	DebugWizard.register_line("movement_graph", "random", Color.ORANGE, 0.0, 100.0)
	DebugWizard.register_step("movement_graph", "jump", Color.RED)
	
	# Create another label
	DebugWizard.create_label("fps_label", "performance")
	
	print("DebugWizard test initialized!")
	print("Press F3 (toggle_debug) to show/hide the debug UI")

func _process(delta: float) -> void:
	time_elapsed += delta
	
	# Simulate bounce value
	bounce_value = abs(sin(time_elapsed * 2.0)) * 100.0
	
	# Random value with some smoothing
	random_value = lerp(random_value, randf() * 100.0, delta * 2.0)
	
	# Simulate jump events every 2 seconds
	jump_timer += delta
	if jump_timer >= 2.0:
		is_jumping = true
		jump_timer = 0.0
	else:
		is_jumping = false
	
	# Simulate health fluctuation
	health = 50.0 + sin(time_elapsed * 0.5) * 50.0
	health_changed.emit(health)
	
	# Send data to debug UI
	DebugWizard.send_args("stats", {
		"time": "%.2f" % time_elapsed,
		"bounce": "%.1f" % bounce_value,
		"random": "%.1f" % random_value
	})
	
	DebugWizard.send_args("wave_graph", {
		"sine": sin(time_elapsed * 3.0),
		"cosine": cos(time_elapsed * 3.0)
	})
	
	DebugWizard.send_args("movement_graph", {
		"bounce": bounce_value,
		"random": random_value,
		"jump": is_jumping
	})
	
	DebugWizard.send_args("fps_label", {
		"FPS": Engine.get_frames_per_second(),
		"delta": "%.4f" % delta
	})


func _on_visibility_changed() -> void:
	pass # Replace with function body.
