extends SceneTree
const Module = preload("res://addons/zuma_minigames/module.gd")
const Demo = preload("res://addons/zuma_minigames/demo.gd")
const Rules = preload("res://addons/zuma_minigames/core/rules.gd")

class FakeTransport extends Node:
	func request(_base, _path, method = HTTPClient.METHOD_GET, _payload = null, _timeout = 3.0) -> Dictionary:
		if method == HTTPClient.METHOD_POST:
			return {"ok": true, "data": {"id": "b".repeat(32), "display_name": "B"}}
		return {"ok": true, "data": {"items": [{"id": "a".repeat(32), "display_name": "A"}, {"id": "b".repeat(32), "display_name": "B"}]}}

func _initialize() -> void:
	call_deferred("run_test")

func run_test() -> void:
	create_timer(5).timeout.connect(func(): quit(2))
	var module = Module.new()
	root.add_child(module)
	assert(module.configure({"storage_dir": "user://ownership_tests/" + Rules.uuid(), "auto_upload": false, "owner_key": "profile:" + "a".repeat(32), "profile_id": "a".repeat(32)}) == OK)
	var demo = Demo.new() # Do not start its normal ready/network flow.
	demo.module = module
	demo.profile_picker = OptionButton.new()
	demo.profile_picker.add_item("Без профиля")
	demo.profile_picker.add_item("A")
	demo.profile_picker.add_item("B")
	demo.profiles = [{"id": "a".repeat(32), "display_name": "A"}, {"id": "b".repeat(32), "display_name": "B"}]
	demo.selected_profile = "a".repeat(32)
	demo.status = Label.new()
	module.delivery_busy = true
	demo.profile_picker.select(2)
	demo._select_profile(2)
	assert(demo.profile_picker.selected == 1 and demo.selected_profile == "a".repeat(32), "busy switch displayed wrong owner")
	var fake := FakeTransport.new()
	root.add_child(fake)
	module.transport = fake
	demo.profile_name = LineEdit.new()
	demo.profile_name.text = "B"
	await demo._create_profile()
	assert(demo.profile_picker.selected == 1 and demo.selected_profile == "a".repeat(32), "failed create/switch changed displayed owner")
	module.delivery_busy = false
	assert(module.outbox.bind_owner("demo-local", "a".repeat(32), module.options.base_url) == OK)
	demo.profile_picker.select(0)
	demo._select_profile(0)
	assert(module.options.profile_id.is_empty())
	assert(not module.outbox.bindings.has(module.options.owner_key), "no-profile selection still has an old route")
	var payload: Dictionary = {"client_run_id": Rules.uuid(), "game_id": "pairs"}
	assert(module.outbox.enqueue(module.options.owner_key, payload) == OK)
	assert(module.outbox.freeze_route(module.outbox.pending()[0]).is_empty())
	demo.profile_picker.free()
	demo.profile_name.free()
	demo.status.free()
	demo.free()
	module.queue_free()
	fake.queue_free()
	await process_frame
	print("MINIGAMES_OWNERSHIP PASS failed switches and fresh unassigned owners")
	quit(0)
