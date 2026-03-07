extends Control
class_name DebugGraph

@onready var graph: DrawGraph
@onready var label_container: VBoxContainer


func _ready():
	graph = $HBoxContainer/Panel
	label_container = $HBoxContainer/VBoxContainer

func populate_legend(text: String, color: Color) -> void:
	var label = Label.new()
	label.text = text
	label.add_theme_color_override("font_color", color)
	label_container.add_child(label)
