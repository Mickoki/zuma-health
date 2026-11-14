extends Control
## A descriptive chart; null values leave gaps, with no health thresholds.

var points: Array = []
var maximum := 10.0

func _ready() -> void:
	custom_minimum_size = Vector2(0, 180)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func set_data(values: Array, scale_maximum: float) -> void:
	points = values.duplicate(true)
	maximum = scale_maximum
	queue_redraw()

func _draw() -> void:
	var background := Color("0d1b2b")
	var grid := Color("31465b")
	var muted := Color("aabed0")
	var accent := Color("55d9c2")
	draw_rect(Rect2(Vector2.ZERO, size), background)
	var left := 52.0
	var right := maxf(left + 1.0, size.x - 22.0)
	var top := 18.0
	var bottom := maxf(top + 1.0, size.y - 25.0)
	for index in range(5):
		var fraction := float(index) / 4.0
		var y := lerpf(bottom, top, fraction)
		draw_line(Vector2(left, y), Vector2(right, y), grid, 1.0)
		draw_string(ThemeDB.fallback_font, Vector2(2, y + 5), "%.1f" % (maximum * fraction), HORIZONTAL_ALIGNMENT_RIGHT, 42, 14, muted)
	if points.is_empty() or maximum <= 0.0:
		return
	var previous := Vector2.ZERO
	var has_previous := false
	for index in range(points.size()):
		var fraction := 0.5 if points.size() == 1 else float(index) / float(points.size() - 1)
		var value: Variant = points[index].value
		if value == null:
			has_previous = false
			continue
		var point := Vector2(lerpf(left, right, fraction), lerpf(bottom, top, clampf(float(value) / maximum, 0.0, 1.0)))
		if has_previous:
			draw_line(previous, point, accent, 2.0, true)
		draw_circle(point, 4.0, accent)
		previous = point
		has_previous = true
