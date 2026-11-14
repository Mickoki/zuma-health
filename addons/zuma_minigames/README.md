# Zuma Minigames

Переносимый модуль для **Godot 4.7.2 Standard / GDScript / Compatibility**.
Четыре игры, инструкции, уровни сложности, результаты, offline-очередь и
доставка в Go API. Главное меню приложения не изменяется.

## Открыть демо

Откройте `demo.tscn` из этой папки в Godot и нажмите F6. Либо из PowerShell:

```powershell
& 'C:\Games\steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe' --path 'C:\Documents\Zuma\zuma-health' --scene res://addons/zuma_minigames/demo.tscn
```

В демо можно выбрать игру/сложность, создать или выбрать серверный профиль,
явно привязать прежние локальные результаты и повторить отправку. Без сервера
игры доступны; без profile_id результаты остаются непривязанными. Новые игры
при выборе «Без серверного профиля» не наследуют ранее привязанный профиль.

Потеря фокуса окна прерывает начатую попытку. Перед включением записи экрана
настройте рекордер, затем вернитесь в окно игры и начинайте. Прерванный результат
сохраняется; «Заново» создаёт новую попытку с новым UUID и случайной раскладкой.

## Подключить к другому приложению

Скопируйте **всю** папку `addons/zuma_minigames` в такую же папку принимающего
проекта. Не нужны Autoload, EditorPlugin, дополнительные InputMap-действия
или сцены главного приложения. Используются собственные ресурсы и локальные
preload, глобальных class_name нет. Минимальный размер области модуля — 960×540.

```gdscript
const Minigames = preload("res://addons/zuma_minigames/module.tscn")
var games

func _ready() -> void:
	games = Minigames.instantiate()
	add_child(games)
	games.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	games.run_finished.connect(_on_result)
	games.delivery_changed.connect(_on_delivery)
	games.module_exit_requested.connect(func(): games.hide())
	var profile_id: String = "<existing 32-character server profile ID>"
	var error: Error = games.configure({
		"base_url": "http://127.0.0.1:8080",
		"profile_id": profile_id,
		"owner_key": "profile:" + profile_id,
		"storage_dir": "user://zuma_minigames",
		"source": "observed",
		"auto_upload": true
	})
	if error != OK:
		push_warning("Delivery configuration error: %d" % error)
	games.start_game("pairs", "normal")

func _on_result(payload: Dictionary) -> void:
	# Called once after completion/abort, even without HTTP.
	print(payload.client_run_id, " ", payload.status)

func _on_delivery(client_run_id: String, state: String, message: String) -> void:
	print(client_run_id, " ", state, " ", message)
```

Публичные методы:

- `configure(options: Dictionary) -> Error`: до активной игры/отправки;
  ERR_BUSY при попытке смены конфигурации в процессе, ERR_INVALID_PARAMETER
  при неверных параметрах. Ошибка диска возвращается явно, но игра остаётся
  доступной, а несохранённый результат удерживается в памяти.
  Необязательный `survey` — сохранённый опрос с четырьмя числовыми полями
  `sleep_hours`, `fatigue`, `stress`, `mood`; его копия фиксируется при запуске
  задания и входит в неизменяемый payload. Пустой словарь сохраняет совместимость
  автономного модуля с прежними прохождениями.
- `start_game(game_id: String, difficulty: String = "easy") -> Error`:
  открывает инструкцию; игра начинается по кнопке «Начать».
- `cancel_game()`: сохраняет активную попытку как aborted, повторно не завершает её.
- `retry_pending()`: одна последовательная попытка доставки накопленных записей.
- `pending_count() -> int`: количество ожидающих/ещё не записанных результатов.
- `bind_owner(owner_key: String, profile_id: String) -> Error`: явная привязка
  ранее локального владельца к профилю. Привязка неизменяема; другой профиль
  требует другого owner_key. Адрес берётся из configure.

Сигналы:

- `run_finished(payload: Dictionary)` — неизменяемый по смыслу журнал прохождения.
- `delivery_changed(client_run_id: String, state: String, message: String)` —
  pending/sending/sent/unassigned/storage_error/storage_warning. Message — текст
  для человека, а не формат для машинного разбора. Серверная квитанция с ID
  доступна в архиве sent; принимающее приложение также может самостоятельно
  отправлять payload и получать server ID, установив auto_upload=false.
- `module_exit_requested()` — игрок нажал «Назад»; host решает, какой экран показать.

Для offline-запуска без профиля передайте пустой profile_id и собственный
устойчивый owner_key. Host должен хранить этот ключ между перезапусками и
разделять локальных игроков. После привязки создавайте новый непривязанный
owner_key для будущих гостей; неизменяемый ключ не означает нового человека.

## Правила

| Игра | Легко / обычно / сложно |
| --- | --- |
| fifteen | 30 / 90 / 180 случайных легальных перемешиваний поля 4×4 |
| pairs | 9 / 12 / 18 пар, показ 5 / 4 / 3 секунды, пауза ошибки 0,7 с |
| math | 20 разных примеров, общий лимит 60 с, на пример 8 / 6 / 4 с |
| chimp | от 5→12 / 6→18 / 9→24 чисел; ошибок максимум 4 / 3 / 2 |

Математический пул: 992 / 6042 / 23880 разных выражений. Коммутативные
перестановки считаются одним выражением. Четыре разных варианта, ровно один
правильный; ответ на границе дедлайна не принимается. Есть ручной пропуск.
В Chimp после выбора 1 числа скрываются; выбор по возрастанию, после ошибки
новая раскладка с тем же количеством, после успеха — на одно число больше.

Настройки нагрузки увеличены на 50% относительно исходного предложения;
это не медицинская/научная оценка сложности. Пятнашки всегда разрешимы;
число перемешиваний не равно оптимальной длине решения. Новый запуск получает
новую раскладку, непосредственно предыдущая в текущей работе модуля не повторяется.

Часы для длительностей монотонны. UTC performed_at — только метка начала.
Назад/Заново/потеря фокуса/удаление активной сцены завершают попытку как aborted.
Технические пределы: 24 часа, 10000 событий, 1 MiB серверного JSON. При
приближении к пределу запись завершается с recording_limit. Synthetic-источник
явно виден в игре и отчёте. Диагнозов и общего балла здоровья нет.

## Очередь и восстановление

По умолчанию данные находятся в `user://zuma_minigames/`:

- pending — owner_key и неизменяемый payload на каждый UUID;
- routes — профиль/локальный URL, зафиксированные до отправки;
- sent — исходный результат, маршрут и подтверждённая серверная квитанция;
- bindings.json — явные неизменяемые привязки владельцев;
- corrupt — повреждённые/незавершённые файлы для восстановления, не удаляются молча.

Запись: временный файл в том же каталоге → flush/close → переименование.
После перезапуска полные временные файлы восстанавливаются, повреждённые
сохраняются с предупреждением. Некорректные вложенные привязки/квитанции
не считаются успешной доставкой. Потерянный ответ безопасен: тот же UUID
даёт 200 с прежним server ID. 409/422 сохраняют запись для диагностики.
После первой сетевой/5xx ошибки остальные записи этого адреса пропускаются,
чтобы не ждать таймаут для каждой; записи других серверов продолжают отправку.
Следующая попытка — вручную или при новом результате.

Смена профиля не меняет старые маршруты. Если очередь не записалась на диск,
payload передаётся host сигналом и удерживается в памяти; перед закрытием
приложения устраните ошибку и повторите сохранение. При физически недоступном
диске гарантировать восстановление после выключения невозможно.

Хранение рассчитано на один процесс/одного worker. Принимающее приложение
должно предотвращать одновременное использование одного каталога несколькими
экземплярами. SQLite и файлы результатов не зашифрованы; права регулирует ОС.
Не публикуйте реальные данные в Git. Для резервной копии остановите приложение
и скопируйте весь каталог очереди вместе с данными сервера.

## Проверки

Из корня проекта, подставив путь к Godot:

```powershell
$godotExe = 'C:\Games\steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe'
& $godotExe --headless --path . --script res://addons/zuma_minigames/tests/test_rules.gd 2>&1
& $godotExe --headless --path . --script res://addons/zuma_minigames/tests/test_module.gd 2>&1
& $godotExe --headless --path . --script res://addons/zuma_minigames/tests/test_outbox.gd 2>&1
& $godotExe --headless --path . --script res://addons/zuma_minigames/tests/test_recovery.gd 2>&1
& $godotExe --headless --path . --script res://addons/zuma_minigames/tests/test_profile_ownership.gd 2>&1
& $godotExe --headless --path . --script res://addons/zuma_minigames/tests/test_layout.gd 2>&1
```

`tests/export_runs.gd -- <absolute-output-dir>` формирует 12 синтетических
прохождений для проверки Go; `tests/playtest_ui.gd -- <absolute-output-dir>`
проходит четыре сложные игры с настоящими GUI mouse events в 960×540 и делает
снимки. Он открывает тестовое окно; не двигайте мышь во время автоматического
прогона. `test_delivery.gd` принимает JSON-конфигурацию и фазу offline/online;
сценарий рассчитан на отдельную тестовую SQLite, не на рабочий профиль.

Точный API: [серверная документация](../../server/docs/minigames.md).
