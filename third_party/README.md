# Third-party notices

The project's own code is offered under the MIT license in `../LICENSE`; the
user confirmed that all project rights holders agree. Third-party components
retain their own licenses.

`godot-4.7-notices.txt` was generated from the official Godot 4.7.stable
binary's `Engine.get_copyright_info()` and `Engine.get_license_info()`. It
contains the engine's embedded component notices and license texts.

`go/` contains the license and notice files from the nine third-party Go modules
reported as linked by `go version -m dist/windows/zuma-server.exe` for the
current server build. The SQLite and libc modules include their own additional
third-party notices. Recheck this list and preserve the required notices when
dependencies, build targets or bundled assets change.

Ollama and the optional Qwen model are separately installed; neither is bundled
in this repository or the supplied client/server binaries. Check their own
licenses and distribution terms if redistributing them. This is a technical
inventory and should be reviewed again when the distributed components change.
