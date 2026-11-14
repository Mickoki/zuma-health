# Проверка backend Zuma

Дата: 2026-11-14 (Asia/Qyzylorda). Проверена реализация в ветке `feat/go-backend`.
Все проверки использовали только явно синтетические данные и временные базы.

## Окружение

- Windows amd64; `go version go1.27.3 windows/amd64`.
- Go-модуль требует Go 1.26+, SQLite-драйвер `modernc.org/sqlite v1.62.0`.
- Локальная Ollama 0.40.16, установленная `qwen3:8b` (ID b54de8fcfb8c).

## Автоматические проверки

Команды из `server/`:

```powershell
go test -count=1 -json ./...
go vet ./...
gofmt -l .
$env:CGO_ENABLED = '0'
go build -o zuma.exe ./cmd/zuma
```

Результат: 58 записей PASS для именованных тестов и подтестов, 0 FAIL;
go vet — exit 0; gofmt — пустой вывод; сборка Windows amd64 — exit 0,
бинарник 21 014 528 байт. Сборка с CGO_ENABLED=0 подтверждает отсутствие
необходимости в C-компиляторе. Тесты cmd/zuma отдельно не выделены: точка входа
проверена запуском реального бинарника. Race detector не запускался.

## Соответствие требованиям

| Требование | Проверенное доказательство |
| --- | --- |
| Среднее/медиана и память | TestCalculateKnownResults: 100/200/300/400 мс → 250 мс, 3/4 → 75%, baseline 200 мс → +50 мс / +25% |
| Отсутствующие данные | TestNoValidReaction: null для среднего/медианы, null comparison без baseline |
| Совместимость baseline | TestIncompatibleBaseline, TestBaselineByPerformedTime, TestSourceIsolation: профиль, протокол, source, строго более раннее время |
| Обязательные поля/нулевые значения | TestValidateRequiredZeroValues, TestValidateBounds, TestValidationResponses |
| Полный HTTP-сценарий | TestFullSessionWorkflow, TestPagination, TestUnknownResources, реальные PowerShell-запросы |
| Сохранность SQLite и миграции | TestPersistenceAfterReopen, TestMigrateTwice, реальный перезапуск с той же базой |
| Атомарность и повторы | TestMissingProfileAtomicity, TestIdempotencyAndConflict, TestConcurrentReplay, TestReplayHTTP |
| Числовая эквивалентность повторов | TestSignedZeroReplay: -0 и 0 не создают конфликт, входные указатели не изменяются |
| Строгие HTTP-ошибки | TestValidationResponses: неверный JSON, неизвестное поле, второе JSON-значение, null/пропущенное поле, диапазон, Content-Type и >256 KiB |
| reaction_ms отсутствует у пропусков | TestNullReactionTimeRejectedForNonValidOutcome: явный null отклоняется для missed и premature |
| Печатный HTML | TestHTMLInjectionEscaped и настоящий GET report.html: 200, имя экранировано, показатели видимы |
| Проверка фактов модели | TestValidFactSelection, TestUnknownFactRejected, TestCrossCategoryRejected, TestExtraFieldsRejected, TestMalformedSelectionRejected, TestMandatoryLimitations |
| Ограничение ресурсов модели | TestOversizedResponse, TestTimeoutReleasesSlot, TestBusy |
| Отмена активной генерации | TestInFlightCancellation: сервер Ollama получает отмену контекста, следующий запрос ready |
| Сохранение готового объяснения при сбоях | TestFailedRegenerationPreservesExplanation, TestInterruptedRegenerationPreservesExplanation (cancel/timeout), реальный offline-перезапуск |
| Устаревание объяснения | TestExplanationFingerprint, TestBackfillInvalidatesExplanation |
| Offline при сбое модели | TestWorkflowWithExternalNetworkDenied, TestUnavailable; настоящий бинарник с ZUMA_OLLAMA_URL=http://127.0.0.1:1 |
| Отсутствие внешних обращений адаптера | TestExternalConnectionsDenied проверяет отказ transport до соединения; внешние base URL отклоняются, proxy отключён |
| Конфигурация локального запуска | TestDefaults, TestRejectNonLoopbackListen, TestInvalidConfig |

## Настоящая Qwen3 8B

Запущен Windows-бинарник на `127.0.0.1:18080` с отдельной тестовой SQLite.
Выполнен `examples/requests.ps1 -BaseUrl http://127.0.0.1:18080 -Explain`:

- POST профиля и сессии успешны; повтор вернул тот же session_id.
- История содержит одну сессию нового профиля.
- Отчёт: median_ms=250, memory_percent=75.
- POST explanation вернул status=ready, model=qwen3:8b.
- Финальная проверка после исправлений: 5 observation-фактов, 3 обязательных
  ограничения (not_medical, synthetic, no_baseline).
- Повторный GET report вернул сохранённое ready-объяснение; HTML — 200.

Это реальный запрос к установленной модели, не mock.

## Перезапуск и недоступная модель

Бинарник остановлен, затем запущен с той же SQLite и
ZUMA_OLLAMA_URL=http://127.0.0.1:1. Проверено:

- ранее созданная сессия осталась в истории;
- /readyz вернул ready, model/status сообщил available=false;
- генерация вернула unavailable, а прежнее готовое объяснение сохранилось;
- числовой и HTML-отчёты доступны (HTML 200, медиана 250 мс);
- новый полный PowerShell-сценарий (профиль, сессия, повтор, история, отчёт)
  прошёл; объяснение честно вернуло unavailable.

Системное подключение к интернету не отключалось и настройки firewall не менялись.
Offline проверен на уровне компонентов: SQLite локальна, модель локальна,
HTTP-транспорт отклоняет внешние адреса и не использует proxy. Для зависимостей
и первоначальной загрузки модели сеть всё ещё нужна, как описано в README.

## Контракт и клиентский пример

OpenAPI 3.1 структурно проверен `@apidevtools/swagger-parser 13.1.0`.
Документированный пример сессии и реальные ответы всех JSON-endpoint проверены
по соответствующим схемам с `ajv 8.20.0` и `ajv-formats 3.0.1`, включая
сохранённый отчёт с ready-объяснением настоящей Qwen. Все проверки PASS.
Эти инструменты использованы для проверки и не являются зависимостями сервера.

`server/examples/client.gd` прошёл синтаксический разбор gdtoolkit 4.5.0.
Godot Engine в окружении не найден; запуск примера внутри Godot и совместная
игровая сборка не проверены. После исходной проверки команда добавила стартовое
меню, полученное из main при подготовке PR; оно не подключено к API, мини-игр
пока нет. Контракт HTTP и числовые результаты проверены независимо от клиента.

## Независимый обзор

Отдельный агент проверил весь backend по утверждённой спецификации и плану.
Critical/Important замечаний не выявлено. Найдены три пограничных пункта:
явный reaction_ms:null, signed zero в повторе и недостаточная проверка
отмены активного запроса. Первые два воспроизведены падающими регрессионными
тестами и исправлены; отмена, освобождение слота и сохранение объяснения
подтверждены дополнительными тестами. После исправлений весь набор пройден заново.

## Ограничения результата

Сервер предназначен для доверенного локального desktop-сценария без авторизации,
шифрования базы и CORS. Это не подтверждённая медицинская система. Qwen выбирает
серверные факты, свободный текст не публикуется. PDF получается печатью HTML
средствами браузера. Данные тестов, веса модели и бинарник исключены из Git.
Исходная проверка завершена до публикации. По последующему запросу пользователя
ветка `feat/go-backend` отправлена на GitHub, создан PR №1 в main. В неё включены
изменения main до `210991e`: стартовое меню и правила .gitignore. Конфликт
add/add в .gitignore разрешён объединением обоих наборов исключений; файлы
сцены/скриптов команды сохранены без изменений. Основная ветка не изменялась.
