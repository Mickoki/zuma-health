extends SceneTree

var app: Control
var failed := false

func check(condition: bool, message: String) -> void:
	if not condition:
		push_error("TEST FAILED: " + message)
		failed = true

func wait_for_reports() -> void:
	for i in range(200):
		if not is_instance_valid(app.trend_loader):
			return
		await create_timer(0.05).timeout

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	app = load("res://scenes/main_menu/main.tscn").instantiate()
	app.api_url = OS.get_environment("ZUMA_TEST_API")
	app.queue_path = OS.get_environment("ZUMA_TEST_QUEUE_DIR").path_join("trends_pending")
	app.draft_path = OS.get_environment("ZUMA_TEST_QUEUE_DIR").path_join("trends_survey.json")
	root.add_child(app)
	for i in range(100):
		if not app.selected_profile.is_empty() and app.profiles.size() >= 2:
			break
		await create_timer(0.05).timeout
	check(app.profiles.size() >= 2, "profiles loaded")
	await app.request(HTTPClient.METHOD_GET, "/test/trend_data")
	app.show_trends()
	for i in range(100):
		if is_instance_valid(app.trend_chart):
			break
		await create_timer(0.05).timeout
	check(is_instance_valid(app.trend_chart), "trend view loaded")
	check(app.trend_protocol.item_count == 2, "protocols shown separately")
	check(app.trend_chart.points.size() == 3, "observed v1 sessions retained including gap")
	check(app.trend_chart.points[0].value == 0 and app.trend_chart.points[1].value == 8 and app.trend_chart.points[2].value == null, "zero retained, gap preserved and values ordered oldest first")
	check("Без значения: 1" in app.trend_summary.text, "missing value reported")
	check(app.trend_chart.maximum == 24, "sleep axis uses declared survey scale")
	app.toggle_trend_values()
	check(app.trend_values.visible and app.trend_values.get_child_count() == 3, "exact values and gaps available")
	app.trend_protocol.select(1)
	app.trend_protocol.item_selected.emit(1)
	check(app.trend_chart.points.size() == 1 and app.trend_chart.points[0].value == 4, "different protocol does not mix")
	app.trend_source.select(1)
	app.trend_source.item_selected.emit(1)
	check(app.trend_chart.points.size() == 1 and app.trend_chart.points[0].value == 11, "synthetic data shown separately")
	app.trend_metric.select(1)
	app.trend_metric.item_selected.emit(1)
	check(app.trend_chart.maximum == 10 and app.trend_chart.points[0].value == 1, "metric selection updates data and scale")
	app.trend_source.select(0)
	app.trend_source.item_selected.emit(0)
	await app.request(HTTPClient.METHOD_GET, "/test/fail_trend_report")
	app.trend_metric.select(4)
	app.trend_metric.item_selected.emit(4)
	await wait_for_reports()
	check(app.trend_chart.points.size() == 3 and app.trend_chart.points[0].value == 60 and app.trend_chart.points[1].value == null and app.trend_chart.points[2].value == 75, "memory uses server reports and leaves unavailable report as gap")
	check(app.trend_retry.visible and "Отчётов недоступно: 1" in app.trend_summary.text, "failed report can be retried")
	app.trend_retry.pressed.emit()
	await wait_for_reports()
	check(app.trend_chart.points[1].value == 80 and not app.trend_retry.visible, "retry loads missing report")
	app.trend_metric.select(5)
	app.trend_metric.item_selected.emit(5)
	await wait_for_reports()
	check(app.trend_chart.points.size() == 3 and app.trend_chart.points[0].value == 300 and app.trend_chart.points[1].value == 250 and app.trend_chart.points[2].value == null, "reaction uses server median and retains null as gap")
	check(app.trend_chart.points[2].reason == "нет действительных попыток" and app.trend_chart.maximum == 300, "reaction gap and automatic scale are explained")
	await app.request(HTTPClient.METHOD_GET, "/test/slow_trend_reports")
	app.show_trends()
	for i in range(100):
		if is_instance_valid(app.trend_chart) and app.trend_chart.is_inside_tree():
			break
		await create_timer(0.05).timeout
	app.trend_metric.select(4)
	app.trend_metric.item_selected.emit(4)
	await create_timer(0.08).timeout
	app.trend_metric.select(0)
	app.trend_metric.item_selected.emit(0)
	await create_timer(0.6).timeout
	check(not is_instance_valid(app.trend_loader) and app.trend_metric.selected == 0 and app.trend_chart.points[0].value == 0, "metric change cancels requests and ignores late responses")
	app.select_profile(1)
	for i in range(100):
		if is_instance_valid(app.trend_summary) and "Нет данных" in app.trend_summary.text:
			break
		await create_timer(0.05).timeout
	check("Нет данных" in app.trend_summary.text and app.trend_chart.points.is_empty(), "profile change clears previous data")
	await app.request(HTTPClient.METHOD_GET, "/test/delay_next_trend")
	app.select_profile(0)
	app.select_profile(1)
	await create_timer(0.8).timeout
	check(app.selected_profile.id == "cccccccccccccccccccccccccccccccc" and app.trend_chart.points.is_empty(), "late response from another profile is ignored")
	if not failed:
		print("TRENDS TEST PASSED")
	quit(1 if failed else 0)
