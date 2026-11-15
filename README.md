# Zuma

The interface uses concise labels, rules before each game, and one foreground
disclaimer. Profile management can be expanded from Overview; local storage
diagnostics are under Help. [UI cleanup checks](docs/interface-cleanup-verification.md).

The interface, reports, model-selected fact text, source comments, test fixtures,
and project documentation are in English. Start the updated client **and**
server to use the English version. Existing profile names and saved user data
remain unchanged. Cached explanations from earlier versions are regenerated
because their fact wording is included in cache validation.
[English localization checks](docs/english-localization-verification.md).

The current redesign is based on Google Stitch mockups: a space background, shared theme,
sidebar navigation, SVG icons, and A4 reports. The survey, History, Trends, and Help
are preserved. Game shortcuts: R — new attempt, Esc — back, 1–4 — answer in
Speed Math; losing focus ends the attempt and opens an overlay.
[Redesign verification](docs/stitch-redesign-verification.md).

Prototype for the NASA Space Apps challenge Create Health Monitoring Software for Astronauts on Space Missions:
https://www.spaceappschallenge.org/2026/challenges/health-monitoring-software/

Workflow: saved survey → one of four minigames → save a run with a survey snapshot → history and report. The local model is optional. Watch integration is excluded.

## Server

Go + SQLite, HTTP API for Godot desktop, JSON/HTML reports, Qwen3 8B through Ollama.
Go performs the calculations. The main workflow works without the model.

```powershell
cd server
go run ./cmd/zuma
```

Requires Go 1.26+. The default API address is http://127.0.0.1:8080.
[Startup and limitations](server/README.md), [OpenAPI](server/docs/openapi.yaml),
[Godot example](server/examples/client.gd), [team plan](PLAN.md).

## Godot client

Open `project.godot` in Godot 4 and run the project (F5). Start the server
separately using the instructions above. On Overview, create a profile or select
an existing one; the refresh button reconnects to the server. The survey saves
a separate draft for each profile in `user://survey_drafts.json` on the device.
For the selected profile, Overview shows the latest saved check and a link
to its report; demonstration data is labeled separately.
Every field in a new survey must be filled in explicitly; zero is also valid.
Unsaved input stays in memory when switching screens until the application closes.
To keep it between launches, click “Save draft”.
History shows sessions in pages of 10 records and opens a report or print version;
the list includes survey answers and the memory task result. Reports show changes
relative to the nearest preceding comparable session, if available, and link to
that session's report.
Trends shows sleep, fatigue, stress, mood, memory score, or median reaction time
from the profile's latest 100 sessions, as well as survey values from the latest
100 game runs. Game data is grouped by game, difficulty, rules version, and source.
Each point's time refers to the game run rather than survey completion; the same
saved survey can appear repeatedly. Legacy memory and reaction measures are
available only for the legacy protocol and are not substituted for the new games.
Memory and reaction values come from reports calculated by the Go server.
Source and protocol are selected separately; spacing between points represents
check order rather than elapsed time. Gaps are not connected by lines.
Exact values and dates can be expanded as a list. The scales are not medical
norms; the reaction scale adjusts automatically to the values.
A model explanation can be requested separately in the report; numerical data
remains available when the model is absent.
Help explains the survey and measures and links to NASA materials.

### Minigames

Create or select a profile, then complete and save the survey. In Games, select
a difficulty and one of four games: Fifteen Puzzle, Find the Pair, Speed Math,
or Remember the Numbers. Each game saves a separate run to a local queue and
tries to send it to the server; unsent results can be retried. Once submitted,
paginated run history and HTML reports are available in the same section,
where a model explanation can also be requested. The profile must first be
created or selected while the server is available. A snapshot of the latest
saved survey is attached to every new run.
If your wellbeing changes, update and save the survey before the next game:
the completion time is not recorded. The four games use their own protocol
rather than the legacy reaction and memory protocol. History for legacy full
checks remains available separately. [Rules, queue, and limitations](addons/zuma_minigames/README.md),
[API and database migration](server/docs/minigames.md).

When updating, stop the old server and back up the database directory:
the schema migration cannot be reversed for the old binary. Queue data and
the database are not encrypted. If writing to disk fails, the result stays
only in the running application's memory; fix the error and retry sending
before closing the application.

To demonstrate legacy reports while the server is running, run
`python server\examples\demo_data.py`: this creates a separate profile with
explicitly labeled synthetic data.

To test the client with a local test API (without a real database), supply
the path to the Godot 4.7 console executable:

```powershell
python tests/run_client_integration.py "C:\path\to\Godot_v4.7-stable_win64_console.exe"
```

## Windows export

If `builds/windows/Zuma-integrated.exe` and `builds/windows/zuma-server.exe`
have already been built, open PowerShell in the project root for a local run,
execute `cd server`, then `..\builds\windows\zuma-server.exe`, and leave the
server window open. In another PowerShell window at the project root, run
`./builds/windows/Zuma-integrated.exe`, or open that file in File Explorer.
With this launch method, the database is in `server/data/`. Builds are excluded
from Git and must be rebuilt when sharing the source.
To build the server, create `builds/windows`, then run
`go build -o ../builds/windows/zuma-server.exe ./cmd/zuma` from `server`.

Open the project in Godot 4.7 and install matching export templates through
**Editor → Manage Export Templates** (Windows x86-64). Create the
`builds/windows` folder, then choose **Project → Export → Windows Desktop → Export
Project**. The preset uses standard installed templates; the build folder is
excluded from Git. To export from PowerShell with the Godot console executable:

```powershell
New-Item -ItemType Directory -Force builds/windows | Out-Null
& 'C:\path\to\Godot_v4.7-stable_win64_console.exe' --headless --path . --export-release 'Windows Desktop' builds/windows/Zuma-integrated.exe
```

The export contains the client and minigames; the Go server runs separately.
Application control policies on some computers may block a new build.
Packaging of dynamically loaded scenes can be checked without the real games:

```powershell
python tests/export_pack_integration.py 'C:\path\to\Godot_v4.7-stable_win64_console.exe'
```

This check creates a separate temporary project with test scenes and removes
it afterward; it does not modify the real project or game files.

An additional test with the real server creates a separate temporary SQLite
database with synthetic data and runs after building the server:

```powershell
python tests/run_real_server_integration.py "C:\path\to\Godot_v4.7-stable_win64_console.exe" "C:\path\to\zuma.exe"
```

If Ollama is running and `qwen3:8b` is already installed, a separate real-model
check uses only a synthetic survey and temporary database without downloading
the model:

```powershell
python tests/run_model_integration.py "builds\windows\zuma-server.exe"
```

It checks the explanation status, required limitations, and report rereading.
If the model is unavailable, the check reports that the result is unconfirmed;
the main application continues working without the model. The test scenario
itself can be checked without the model using `python tests/test_model_probe.py
builds/windows/zuma-server.exe`: this uses only a test substitute for Ollama
and does not verify the real model.

Do not store real medical data, secrets, builds, or model weights in Git.
Task results are descriptive measures, not a diagnosis.
English team description draft: [Space Apps submission draft](docs/space-apps-submission-en.md).
The project's own code uses the [MIT license](LICENSE); the user has confirmed
consent from all copyright holders. [Third-party components](third_party/README.md)
retain their own licenses, which must be considered when distributing them.
