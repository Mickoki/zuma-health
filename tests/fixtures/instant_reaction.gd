extends Control
signal completed(result: Dictionary)
signal cancelled

func _ready() -> void:
	completed.emit({"protocol_version": "reaction-memory-v1", "trials": [{"outcome": "valid", "reaction_ms": 280}]})
