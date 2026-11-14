# Zuma

Прототип для задачи NASA Space Apps Create Health Monitoring Software for Astronauts on Space Missions:
https://www.spaceappschallenge.org/2026/challenges/health-monitoring-software/

Сценарий: опрос → задания на реакцию и память → сохранение → история и отчёт →
опциональное объяснение локальной модели. Интеграция часов исключена.

## Сервер

Go + SQLite, HTTP API для Godot desktop, JSON/HTML-отчёты, Qwen3 8B через Ollama.
Расчёты выполняет Go. Основной сценарий работает без модели.

```powershell
cd server
go run ./cmd/zuma
```

Нужен Go 1.26+. API по умолчанию http://127.0.0.1:8080.
[Запуск и ограничения](server/README.md), [OpenAPI](server/docs/openapi.yaml),
[Godot-пример](server/examples/client.gd), [план команды](PLAN.md).

## Клиент Godot

Четыре мини-игры доступны отдельным переносимым модулем
[addons/zuma_minigames](addons/zuma_minigames/README.md): пятнашки, поиск пар,
математика на скорость и запоминание чисел. Откройте
`addons/zuma_minigames/demo.tscn` и нажмите F6. Основное меню автоматически
не подключалось. [API прохождений](server/docs/minigames.md).

Есть project.godot, профиль экспорта Windows и стартовая сцена
scenes/main_menu/main.tscn со скриптом scripts/main_menu.gd, добавленные командой.
Меню пока не подключено к серверу и новому модулю; единый пользовательский сценарий
ещё предстоит собрать. Надписи статуса в стартовом меню — заглушки прежнего
плана, а актуальная архитектура описана в server/README.md. Пример GDScript
не запускается автоматически. Шаблоны экспорта устанавливаются отдельно.

Не храните реальные медицинские данные, секреты, сборки и веса модели в Git.
Результаты заданий — описательные показатели, не диагноз.
