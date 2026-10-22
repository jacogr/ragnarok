# Current command executable and durable partial progress

Gray Paper `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d` remains primary. This qualification layer
changes only independent test/tooling sources. The actual shipped integration/offload executable
runs `download-current` against a separate native TLS responder; Python owns bounded process,
exit/output and cleanup assertions, while Nim owns exact protocol requests and complete durable maps.

Six cases cover journal and managed success, replay and empty-response refusal after one adoption,
whole-command timeout after one adoption, and rejection of the legacy policy header before any
database creation. Partial cases request two children. The responder verifies the second request
uses an independent full sealed-header hash of the first actual child, then deliberately refuses
that continuation. All three report adopted=1/requested=2, and strict reopen compares every state
entry and retained history against the independently composed genuine current child. This does
not claim two successful consecutive current children or remote ancestor acquisition.

The declared `application_current_download` E2E workload builds the shipped ARC/Clang LTO checked
profile with both integration/offload defines. Its native witness uses pristine production ABIs.
Failed builds, altered fixture identities, missing readiness, application timeouts and failed native
witnesses remain failures; every exceptional process path reaps its responder. Python discovery
covers malformed/dead readiness, stale-build refusal, CLI-success/native-failure separation and
terminate/kill/reap timeout escalation.

Local macOS evidence: all six actual executable cases, focused semantic checking and pinned
formatter idempotence passed. The executable reused the successful identical-production-source
`make build` from the command layer; the selected workload retained its binary digest/build log.
Full E2E-plan or exact-head Linux CI success is not claimed. M1 framing remains separate from
complete state serialization, and full JAM/ThinVRF parity remains outside this increment.

`make check-python` passed 768 tests (three skipped); inventory and changed-source formatting
checks also passed. These remain independent harness/native verdicts.
