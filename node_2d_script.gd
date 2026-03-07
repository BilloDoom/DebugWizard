extends Node2D

## Second scene script for testing DebugWizard across scene transitions

signal position_updated(pos: Vector2)
signal speed_changed(speed: float)
signal collision_detected(hit: bool)

var time_elapsed: float = 0.0
var move_speed: float = 100.0
var position_offset: Vector2 = Vector2.ZERO

func _ready() -> void:
	await get_tree().process_frame
	
	 #Create debug elements for this scene
	DebugWizard.create_label("scene2_info", "scene2")
	
	DebugWizard.create_graph("scene2_graph", "scene2")
	DebugWizard.register_line("scene2_graph", "pos_x", Color.RED, -500.0, 500.0)
	DebugWizard.register_line("scene2_graph", "pos_y", Color.GREEN, -500.0, 500.0)
	DebugWizard.register_line("scene2_graph", "speed", Color.YELLOW, 0.0, 200.0)
	
	print("Scene 2 loaded - DebugWizard elements registered")

func _process(delta: float) -> void:
	time_elapsed += delta
	
	# Simulate movement
	position_offset.x = sin(time_elapsed * 2.0) * 200.0
	position_offset.y = cos(time_elapsed * 1.5) * 150.0
	
	# Simulate speed variation
	move_speed = 100.0 + sin(time_elapsed * 3.0) * 50.0
	
	# Emit signals for registered tracking
	position_updated.emit(position_offset)
	speed_changed.emit(move_speed)
	collision_detected.emit(int(time_elapsed) % 3 == 0)
	
	 #Send data to debug UI
	DebugWizard.send_args("scene2_info", {
		"time": "%.2f" % time_elapsed,
		"scene": "Node2D"
	})
	
	DebugWizard.send_args("scene2_graph", {
		"pos_x": position_offset.x,
		"pos_y": position_offset.y,
		"speed": move_speed
	})
