# Verification

Requires Go 1.26+, Python 3, Godot 4, and Windows export templates.
Replace `godot` with the editor executable path where needed.

## Server

```powershell
cd server
go test -count=1 ./...
go vet ./...
go build ./cmd/zuma
cd ..
```

## Client and resources

```powershell
godot --headless --editor --path . --import
python tests/test_english_sources.py
python tests/run_client_integration.py godot
godot --headless --path . --script tests/clean_interface.gd
godot --headless --path . --script tests/english_layout.gd
python tests/export_pack_integration.py godot
```

Run the self-contained addon checks `test_layout`, `test_module`, `test_outbox`,
`test_profile_ownership`, `test_recovery`, `test_redesign`, and `test_rules` in
`addons/zuma_minigames/tests/` using
`godot --headless --path . --script PATH.gd`. Delivery and upload checks require
their documented fixture arguments and a test server. Check logs for script
errors as well as the exit status.

## Release

```powershell
./scripts/build-windows.ps1 -Godot 'C:\path\to\godot.exe'
python tests/run_real_server_integration.py godot dist/windows/zuma-server.exe
```

Read runner usage before invoking optional model checks in
`tests/run_model_integration.py` and `tests/test_model_probe.py`.
Ollama and Qwen3 8B are installed separately.
Integration runners use synthetic profiles and disposable data.
Finally launch the package on a target Windows machine, complete each game,
and open a report. Automated checks do not establish medical validity.
