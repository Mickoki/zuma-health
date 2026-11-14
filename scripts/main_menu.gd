extends Control

func _ready() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 48)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 20)
	margin.add_child(column)
	var title := Label.new()
	title.text = "ZUMA / MISSION HEALTH"
	title.add_theme_font_size_override("font_size", 40)
	column.add_child(title)
	var description := Label.new()
	description.text = "Стартовый проект готов к разработке.\nРеакция • память • самочувствие • отчёт"
	description.add_theme_font_size_override("font_size", 22)
	column.add_child(description)
	var status := Label.new()
	status.text = "Умные часы: не подключены\nЛокальная модель: не настроена\nМини-игры: следующий этап разработки"
	column.add_child(status)
	var check := Button.new()
	check.text = "Проверить локальное сохранение"
	check.custom_minimum_size.y = 52
	column.add_child(check)
	var result := Label.new()
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(result)
	check.pressed.connect(func() -> void:
		var file := FileAccess.open("user://setup_check.json", FileAccess.WRITE)
		if file == null:
			result.text = "Ошибка сохранения: " + str(FileAccess.get_open_error())
			return
		file.store_string(JSON.stringify({"setup": "ok", "time": Time.get_datetime_string_from_system()}))
		file.close()
		result.text = "Запись сохранена: " + ProjectSettings.globalize_path("user://setup_check.json")
	)
	var quit := Button.new()
	quit.text = "Выход"
	quit.custom_minimum_size.y = 48
	quit.pressed.connect(func() -> void: get_tree().quit())
	column.add_child(quit)

