extends Control
class_name DrawGraph

@export var max_points: int = 120
@export var auto_scale := true
@export var auto_resize := false
@export var resolution: int = 1

var lines: Dictionary = {}
var steps: Dictionary = {}

func add_line(id: String, color: Color, d_min: float, d_max: float, amplitude: float = 1.0) -> void:
	if lines.has(id):
		return
	lines[id] = {"values": [], "color": color,  "max": d_max, "min": d_min, "amplitude": amplitude}

func add_step(id: String, color: Color) -> void:
	if steps.has(id):
		return
	steps[id] = {"values": [], "color": color, "type": "step"}

func add_line_value(id: String, value: float) -> void:
	if not lines.has(id):
		return
	
	var arr : Array = lines[id]["values"]
	arr.append(value)
	
	if arr.size() > max_points:
		arr.pop_front()


	if auto_resize:
		var min_v = arr[0]
		var max_v = arr[0]
		for v in arr:
			min_v = min(min_v, v)
			max_v = max(max_v, v)
		lines[id]["max"] = max_v
		lines[id]["min"] = min_v
	
	if auto_scale and not auto_resize:
		lines[id]["max"] = max(lines[id]["max"], abs(value))
		lines[id]["min"] = min(lines[id]["min"], value)
	
	queue_redraw()

func add_step_value(id: String, triggered: bool) -> void:
	if not steps.has(id):
		return
	
	var arr : Array = steps[id]["values"]
	arr.append(triggered)
	
	if arr.size() > max_points:
		arr.pop_front()
	
	queue_redraw()

func clear_line(id: String) -> void:
	if lines.has(id):
		lines[id]["values"].clear()
		queue_redraw()


func _draw():
	var w = size.x
	var h = size.y

	draw_line(Vector2(0, h), Vector2(w, h), Color.DIM_GRAY)
	draw_line(Vector2(0, h / 2), Vector2(w, h / 2), Color.DIM_GRAY)
	draw_line(Vector2(0, 0), Vector2(w, 0), Color.DIM_GRAY)

	for id in lines.keys():
		var data = lines[id]
		var values = data["values"]
		var color = data["color"]
		
		var min_v = data["min"]
		var max_v = data["max"]
		var d_range = max_v - min_v
		if d_range == 0:
			d_range = 1.0
		
		var amplitude = data["amplitude"]

		if values.size() < 2:
			continue
		
		var step = w / float(max_points)

		var buffer = []

		for i in range(0, values.size() - 1, resolution):
			var x1 = i * step
			var y1 = h - ((values[i] * amplitude - min_v) / d_range) * h
			y1 = clampf(y1, 0, h)
			buffer.append(Vector2(x1,y1))
		
		if buffer.size() >= 2:
			draw_polyline(buffer, color, 1)
	
	for id in steps.keys():
		var data = steps[id]
		var values = data["values"]
		var color = data["color"]
		
		if values.size() < 1:
			continue
		
		var step = w / float(max_points)
		for i in range(values.size()):
			if values[i]:
				var x = i * step
				draw_line(Vector2(x, 0), Vector2(x, h), color, 2.0)
