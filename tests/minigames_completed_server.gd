extends SceneTree

const Generator = preload("res://addons/zuma_minigames/core/generator.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	create_timer(35).timeout.connect(func(): push_error("COMPLETED GAMES TEST TIMEOUT"); quit(2))
	var app = load("res://scenes/main_menu/main.tscn").instantiate()
	app.api_url = OS.get_environment("ZUMA_TEST_API")
	app.queue_path = OS.get_environment("ZUMA_TEST_QUEUE_DIR").path_join("complete-sessions")
	app.draft_path = OS.get_environment("ZUMA_TEST_QUEUE_DIR").path_join("complete-drafts.json")
	root.add_child(app)
	await process_frame
	app.selected_profile = {"id": OS.get_environment("ZUMA_TEST_PROFILE_ID"), "display_name": "Synthetic test crew"}
	app.drafts[app.selected_profile.id] = {"sleep_hours": 8.0, "fatigue": 0.0, "stress": 2.0, "mood": 7.0}
	app.show_minigames()
	var host = app.minigames_host
	assert(host.visible)
	assert(host.module.configure({"storage_dir": OS.get_environment("ZUMA_TEST_QUEUE_DIR").path_join("complete-games"), "source": "synthetic", "auto_upload": false}) == OK)
	for game in ["fifteen", "pairs", "math", "chimp", "pairs"]:
		host._launch(game)
		await process_frame
		var view = host.module.view
		view.start_button.pressed.emit()
		var session = view.session
		match game:
			"fifteen":
				var blank := 15
				var solution: Array = []
				for index in session.initial.scramble:
					solution.append(blank)
					blank = index
				solution.reverse()
				for index in solution:
					if session.done:
						break
					view.grid.get_child(index).pressed.emit()
			"pairs":
				while view.elapsed() < session.config.preview_ms + 20:
					await process_frame
				for symbol in range(session.config.pairs):
					var first: int = session.cards.find(symbol)
					var second: int = session.cards.find(symbol, first + 1)
					view.grid.get_child(first).pressed.emit()
					view.grid.get_child(second).pressed.emit()
			"math":
				while not session.done:
					var q: Dictionary = session.initial.questions[session.question_index]
					view.grid.get_child(q.options.find(Generator.answer(q))).pressed.emit()
			"chimp":
				while not session.done:
					for cell in session.positions.duplicate():
						view.grid.get_child(cell).pressed.emit()
					if not session.done:
						view.next_button.pressed.emit()
		assert(session.done and session.result.status == "completed", game)
		host._back_to_menu()
	assert(host.module.pending_count() == 5)
	host.module.retry_pending()
	while host.module.delivery_busy:
		await process_frame
	assert(host.module.pending_count() == 0)
	var response: Dictionary = await host.module.transport.request(app.api_url, "/api/v1/profiles/%s/game-runs?limit=100" % host.profile_id)
	assert(response.ok and response.data.total == 10) # Five aborted runs from the preceding test.
	var completed := 0
	var compared_pairs := 0
	for item in response.data.items:
		if item.status != "completed":
			continue
		completed += 1
		assert(item.source == "synthetic" and item.survey.sleep_hours == 8 and item.survey.fatigue == 0)
		var report: Dictionary = await host.module.transport.request(app.api_url, "/api/v1/game-runs/%s/report" % item.id)
		assert(report.ok and report.data.status == "completed" and report.data.survey.mood == 7)
		if item.game_id == "pairs" and report.data.baseline_run_id != null:
			compared_pairs += 1
	assert(completed == 5 and compared_pairs == 1)
	app.queue_free()
	await process_frame
	print("COMPLETED MINIGAMES REAL SERVER PASS")
	quit()
