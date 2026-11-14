extends "res://scripts/session_queue.gd"

func enqueue(_profile_id: String, _survey: Dictionary, _reaction: Dictionary, _memory: Dictionary) -> Dictionary:
	return {"ok": false, "error": "storage_unavailable"}
