# Managed work-submission CPU and source lifetime

Target: JAMNP-S `aa0e2b8498c0b1bc1725af2903704d701c6577ab` CE133/146 and Gray Paper
`fad0ded4a433052397bf7234352a57fe491883f7`. This extends the
[admission boundary](jamnp-work-submission.md) through the existing single managed proof worker.

The Services owner retains one bounded submission session between the authorization and body
stages. Native/host actors receive detached geometry and opaque session/worker tokens. Canonical
source owners, successful authorization grants and completed refinement remain inside Services
and the leased job. A session reserves capacity until exact completion or explicit retirement.

Authorization and body/refinement are separate CPU turns. Every staging helper retires its selected
state aliases before worker admission. RPC and other canonical consumers remain excluded through
Queued, Running, cancellation and Done until exact collection or joined stop. Between CPU turns,
network delivery does not occupy the proof-worker lease. Session abandonment marks scalar state;
source-bearing ARC fields are released only when the shared graph is available, including when an
unrelated job owns an uncollected Done result. Close joins before releasing the session.

The first turn checks C(1), source C(3) mappings and the actual historical authorizer. The second
turn verifies original-bound inputs and executes the existing complete refinement pipeline. That
pipeline currently reexecutes authorization against the same immutable original source; this is
bounded duplicate work, not trust in a substituted trace or caller-created success. Source selection
and original policy cannot be replaced between turns. Neither result implies report credentials,
availability publication, chain inclusion or canonical adoption.

Completion checks must cover real successful two-stage execution, default/foreign/stale tokens,
Busy through Done, cancellation/stop, body failure, late abandonment, foreign replacement Done
preservation, full/light refusal and repeated source release. Composite worker/Services lowering
must continue to reject copies. Live staged framing and CE133 availability fetch remain next.

## Observed evidence

Local pinned checked-ARC/Clang verification passed on master
`28f7c2c783c5c9f2bc4cb66654b9abb9266e7630` plus this native stack:

- `jamnp_managed_work_submission`: actual Tiny-profile CE146 and CE133 authorization/body/refinement,
  body rejection, stale/foreign controls, cancelled Done, foreign Done during body wait, external stop
  followed by replacement Done, joined close and 1000 private source-release cycles (40816 bytes
  before/after). The first registry attempt rejected a redundant unsupported `offload` requirement;
  using the runner's existing profile resolved it without changing the harness.
- `application_proof_worker`, `application_proof_services` and `light_runtime`: shared lease consumers,
  including a refusal assertion at actual successful light startup.
- `jamnp_ticket_production` (1000 cycles, 87312 bytes unchanged) and `jamnp_node_service`
  (1000 cycles, 39664 bytes unchanged): existing producer and transport behavior remain verified.
- Fresh actual lowering rejected duplication of both `StateProofWorker` and `Services` with their
  intended unavailable `=dup` diagnostics. New ARC fields delegate through both ownership hooks and
  every start, submit, collection and joined cleanup path.
- `make build`, `make format-check` and `make check-inventory` passed. Generated C emitted existing
  self-comparison and Darwin stdlib `stat` binding warnings; no dependency/compiler modification was made.

Only the managed fixture's profile was subsequently tightened from its inherited synthetic CPU
profile to actual Tiny parameters; its complete suite passed again with unchanged ARC accounting.
Production code and other checked consumers were unchanged. These are local results, not Linux CI.
