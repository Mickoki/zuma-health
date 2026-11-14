extends Control
signal completed(result: Dictionary)
signal cancelled

func _ready() -> void:
	var test_button := get_node_or_null("TestAction") as Button
	if test_button != null:
		test_button.pressed.connect(func() -> void: completed.emit({"protocol_version": "reaction-memory-v1", "trials": [{"outcome": "valid", "reaction_ms": 250}]}))
