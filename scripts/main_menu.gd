extends Control

func _ready() -> void:
	var label := Label.new()
	label.text = "ZUMA / MISSION HEALTH\nСтартовый проект готов к разработке."
	label.position = Vector2(48, 48)
	label.add_theme_font_size_override("font_size", 32)
	add_child(label)
