# Zuma backend verification

Date: 2026-11-14 (Asia/Qyzylorda). Verified the implementation on branch `feat/go-backend`.
All checks used explicitly synthetic data and temporary databases only.

## Environment

- Windows amd64; `go version go1.27.3 windows/amd64`.
- The Go module requires Go 1.26+; SQLite driver `modernc.org/sqlite v1.62.0`.
- Local Ollama 0.40.16 with `qwen3:8b` installed (ID b54de8fcfb8c).

## Automated checks

Commands from `server/`:

```powershell
go test -count=1 -json ./...
go vet ./...
gofmt -l .
$env:CGO_ENABLED = '0'
go build -o zuma.exe ./cmd/zuma
```

Result: 58 PASS records for named tests and subtests, 0 FAIL;
go vet exited 0; gofmt produced no output; the Windows amd64 build exited 0,
with a binary size of 21 014 528 bytes. Building with CGO_ENABLED=0 confirms that
no C compiler is required. cmd/zuma has no separate tests: the entry point
was checked by running the actual binary. The race detector was not run.

## Requirements coverage

| Requirement | Verified evidence |
| --- | --- |
| Mean/median and memory | TestCalculateKnownResults: 100/200/300/400 ms → 250 ms, 3/4 → 75%, baseline 200 ms → +50 ms / +25% |
| Missing data | TestNoValidReaction: null mean/median, null comparison without a baseline |
| Baseline compatibility | TestIncompatibleBaseline, TestBaselineByPerformedTime, TestSourceIsolation: profile, protocol, source, strictly earlier time |
| Required fields/zero values | TestValidateRequiredZeroValues, TestValidateBounds, TestValidationResponses |
| Complete HTTP workflow | TestFullSessionWorkflow, TestPagination, TestUnknownResources, real PowerShell requests |
| SQLite persistence and migrations | TestPersistenceAfterReopen, TestMigrateTwice, real restart with the same database |
| Atomicity and replays | TestMissingProfileAtomicity, TestIdempotencyAndConflict, TestConcurrentReplay, TestReplayHTTP |
| Numeric equivalence in replays | TestSignedZeroReplay: -0 and 0 do not conflict; input pointers remain unchanged |
| Strict HTTP errors | TestValidationResponses: malformed JSON, unknown field, second JSON value, null/missing field, bounds, Content-Type, and >256 KiB |
| reaction_ms absent for skipped attempts | TestNullReactionTimeRejectedForNonValidOutcome: explicit null rejected for missed and premature |
| Printable HTML | TestHTMLInjectionEscaped and actual GET report.html: 200, escaped name, visible metrics |
| Model fact validation | TestValidFactSelection, TestUnknownFactRejected, TestCrossCategoryRejected, TestExtraFieldsRejected, TestMalformedSelectionRejected, TestMandatoryLimitations |
| Model resource limits | TestOversizedResponse, TestTimeoutReleasesSlot, TestBusy |
| Active generation cancellation | TestInFlightCancellation: the Ollama server receives context cancellation, next request ready |
| Preserving ready explanations on failure | TestFailedRegenerationPreservesExplanation, TestInterruptedRegenerationPreservesExplanation (cancel/timeout), real offline restart |
| Explanation invalidation | TestExplanationFingerprint, TestBackfillInvalidatesExplanation |
| Offline behavior when the model fails | TestWorkflowWithExternalNetworkDenied, TestUnavailable; actual binary with ZUMA_OLLAMA_URL=http://127.0.0.1:1 |
| No external adapter connections | TestExternalConnectionsDenied checks transport rejection before connecting; external base URLs rejected, proxy disabled |
| Local launch configuration | TestDefaults, TestRejectNonLoopbackListen, TestInvalidConfig |

## Real Qwen3 8B

Started the Windows binary on `127.0.0.1:18080` with a separate test SQLite database.
Ran `examples/requests.ps1 -BaseUrl http://127.0.0.1:18080 -Explain`:

- Profile and session POSTs succeeded; replay returned the same session_id.
- History contained one session for the new profile.
- Report: median_ms=250, memory_percent=75.
- POST explanation returned status=ready, model=qwen3:8b.
- Final check after fixes: 5 observation facts, 3 mandatory
  limitations (not_medical, synthetic, no_baseline).
- Another GET report returned the saved ready explanation; HTML returned 200.

This was an actual request to the installed model, not a mock.

## Restart and unavailable model

Stopped the binary, then restarted it with the same SQLite database and
ZUMA_OLLAMA_URL=http://127.0.0.1:1. Verified:

- The previously created session remained in history.
- /readyz returned ready; model/status reported available=false.
- Generation returned unavailable, while the previous ready explanation was retained.
- Numeric and HTML reports were available (HTML 200, median 250 ms).
- A new complete PowerShell workflow (profile, session, replay, history, report)
  passed; the explanation accurately returned unavailable.

The system internet connection was not disabled, and firewall settings were unchanged.
Offline behavior was checked at the component level: SQLite is local, the model is local,
and the HTTP transport rejects external addresses and does not use proxies. Network access
is still required for dependencies and the initial model download, as described in the README.

## Contract and client example

OpenAPI 3.1 was structurally validated with `@apidevtools/swagger-parser 13.1.0`.
The documented session example and actual responses from all JSON endpoints were validated
against their respective schemas using `ajv 8.20.0` and `ajv-formats 3.0.1`, including
the saved report with a ready explanation from real Qwen. All checks passed.
These tools were used for verification and are not server dependencies.

`server/examples/client.gd` passed syntax parsing with gdtoolkit 4.5.0.
Godot Engine was not found in the environment; running the example inside Godot and
the combined game build were not verified. After the original verification, the team added
the start menu obtained from main while preparing the PR; it is not connected to the API,
and there are no minigames yet. The HTTP contract and numeric results were checked independently of the client.

## Independent review

A separate agent reviewed the entire backend against the approved specification and plan.
No Critical/Important findings were identified. Three edge cases were found:
explicit reaction_ms:null, signed zero in replays, and insufficient testing of
active request cancellation. The first two were reproduced with failing regression
tests and fixed; cancellation, slot release, and explanation preservation
were confirmed by additional tests. The full suite was rerun after the fixes.

## Limitations of the result

The server is intended for a trusted local desktop workflow without authentication,
database encryption, or CORS. It is not a validated medical system. Qwen selects
server facts; free-form text is not published. PDF is produced by printing HTML
through the browser. Test data, model weights, and the binary are excluded from Git.
The original verification was completed before publication. At the user's subsequent request,
branch `feat/go-backend` was pushed to GitHub and PR #1 targeting main was created. It includes
main changes through `210991e`: the start menu and .gitignore rules. The
add/add conflict in .gitignore was resolved by combining both sets of exclusions;
the team's scene/script files were preserved unchanged. The main branch was not modified.
