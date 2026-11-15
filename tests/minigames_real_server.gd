extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	create_timer(20).timeout.connect(func(): push_error("MINIGAMES REAL SERVER TIMEOUT"); quit(2))
	var app = load("res://scenes/main_menu/main.tscn").instantiate()
	app.api_url = OS.get_environment("ZUMA_TEST_API")
	root.add_child(app)
	await process_frame
	app.selected_profile = {"id": OS.get_environment("ZUMA_TEST_PROFILE_ID"), "display_name": "Synthetic test crew"}
	app.drafts[app.selected_profile.id] = {"sleep_hours": 8.0, "fatigue": 0.0, "stress": 2.0, "mood": 7.0}
	app.show_minigames()
	var host = app.minigames_host
	assert(host.visible and host.profile_id == app.selected_profile.id)
	assert(host.module.configure({"storage_dir": OS.get_environment("ZUMA_TEST_QUEUE_DIR").path_join("games"), "source": "synthetic", "auto_upload": false}) == OK)
	for game in ["fifteen", "pairs", "math", "chimp"]:
		host._launch(game)
		await process_frame
		host.module.view.start_button.pressed.emit()
		host.module.cancel_game()
		host._back_to_menu()
	assert(host.module.pending_count() == 4)
	host.module.retry_pending()
	while host.module.delivery_busy:
		await process_frame
	assert(host.module.pending_count() == 0)
	var result: Dictionary = await host.module.transport.request(app.api_url, "/api/v1/profiles/%s/game-runs?limit=20" % host.profile_id)
	assert(result.ok and result.data.total == 4)
	for item in result.data.items:
		assert(item.source == "synthetic" and item.status == "aborted")
		assert(item.survey.sleep_hours == 8 and item.survey.fatigue == 0)
		var report: Dictionary = await host.module.transport.request(app.api_url, "/api/v1/game-runs/%s/report" % item.id)
		assert(report.ok and report.data.source == "synthetic")
		assert(report.data.survey.stress == 2 and report.data.survey.mood == 7)
	# An unreachable old server must not prevent another route from being sent.
	var archive_names := DirAccess.get_files_at(host.module.outbox.root_dir.path_join("sent"))
	assert(not archive_names.is_empty())
	var archive: Dictionary = host.module.outbox.read_dict(host.module.outbox.root_dir.path_join("sent").path_join(archive_names[0]))
	var offline_payload: Dictionary = archive.record.payload.duplicate(true)
	var online_payload: Dictionary = archive.record.payload.duplicate(true)
	offline_payload.client_run_id = "00000000-0000-4000-8000-000000000001"
	online_payload.client_run_id = "ffffffff-ffff-4fff-8fff-ffffffffffff"
	assert(host.module.outbox.bind_owner("offline-test", host.profile_id, "http://127.0.0.1:1") == OK)
	assert(host.module.outbox.enqueue("offline-test", offline_payload) == OK)
	assert(host.module.outbox.enqueue("profile:" + host.profile_id, online_payload) == OK)
	assert(host.module.outbox.pending()[0].payload.client_run_id == offline_payload.client_run_id)
	host.module.retry_pending()
	while host.module.delivery_busy:
		await process_frame
	var retained: Array = host.module.outbox.pending()
	assert(retained.size() == 1 and retained[0].payload.client_run_id == offline_payload.client_run_id)
	var updated: Dictionary = await host.module.transport.request(app.api_url, "/api/v1/profiles/%s/game-runs?limit=20" % host.profile_id)
	assert(updated.ok and updated.data.total == 5)
	host._close()
	app.show_home()
	for i in range(100):
		if is_instance_valid(app.home_game_latest_section) and app.home_game_latest_section.get_child_count() >= 2:
			break
		await create_timer(0.05).timeout
	assert(app.home_game_latest_section.get_child_count() >= 2)
	app.show_trends()
	for i in range(100):
		if is_instance_valid(app.trend_protocol) and app.trend_protocol.is_inside_tree():
			break
		await create_timer(0.05).timeout
	app.trend_source.select(1)
	app.trend_source.item_selected.emit(1)
	var found := false
	for i in range(app.trend_protocol.item_count):
		if str(app.trend_protocol.get_item_metadata(i)).begins_with("zuma-game/"):
			app.trend_protocol.select(i)
			app.trend_protocol.item_selected.emit(i)
			found = true
			break
	assert(found and not app.trend_chart.points.is_empty() and app.trend_chart.points.back().value == 8)
	app.queue_free()
	await process_frame
	print("MINIGAMES REAL SERVER PASS")
	quit()
