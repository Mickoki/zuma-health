# Backend: verified starting conditions

Date: 2026-11-14.

## Team task

The Go server accepts surveys and game results from Godot, stores data,
calculates measures, and produces a report. Local Qwen3 8B through Ollama
explains the calculated results. The user excluded watch integration.
The main workflow must work without internet access and when the model is unavailable.

## Repository state

At the time of inspection, main contained only README.md, PLAN.md, project.godot,
and export_presets.cfg. There was no server code, data schema, or API contract.
README.md and PLAN.md mentioned watches; that information was outdated relative
to the user's decision. The startup scene referenced in project.godot was missing.

## Environment check

- `go version`: `go1.27.3 windows/amd64`.
- `GET http://127.0.0.1:11434/api/version`: Ollama version `0.40.16`.
- `ollama list`: model `qwen3:8b`, ID `b54de8fcfb8c`, size 5.2 GB.
- Model text generation had not yet been tested.

## Protocol and dependencies

Official Ollama documentation describes `POST /api/chat` with the fields
`model`, `messages`, `stream`, `format`, and `think`. A regular JSON response
requires explicitly setting `stream: false`; response content is in
`message.content`. The `format` field accepts a JSON Schema, but the response
must still be validated in Go. JSON structure alone does not establish the
factual accuracy of model text.

The `modernc.org/sqlite` driver is implemented in Go and does not require cgo.
This makes it possible to consider building the Windows server without a
separate C compiler or database server installation. The dependency version
and its build had not yet been checked.

Sources:

- https://docs.ollama.com/api/chat
- https://docs.ollama.com/capabilities/structured-outputs
- https://pkg.go.dev/modernc.org/sqlite

## Design decision

The user chose a single Go server with SQLite and an HTTP connection to Ollama.
Draft specification: `superpowers/specs/2026-11-14-backend-design.md`.
The user approved the specification; implementation was completed in `server/`.
Current evidence: `../server/docs/verification.md`.

When publishing the backend in a separate branch, main changes through 210991e
were incorporated: the team added the startup scene and menu script. The
initial description of missing scenes above refers to the state at the time
of investigation.
