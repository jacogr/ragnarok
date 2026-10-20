# Worker-driven one-child download dispatcher

Scope: connect the existing managed Services lease to CE 128 raw download reception and the
production download command. Protocol/specification pins, plain ARC, compiler, dependencies,
wire bytes and exact-parent certificate authority remain unchanged.

Preparing starts only after complete exact reception and actual native stream retirement. One
Services worker borrows the stable nested raw input and canonical graph. Dispatcher turns poll
native endpoints and independent UI work without copying, clearing or examining captured graph
owners; RPC and canonical access remain gated. All pre-existing external aliases must remain
untouched and alive until collection or joined close. Services, dispatcher and input addresses
remain stable. Successful collection queues the genuine finalized certificate; only a subsequent
host adoption tick and consumed Services result report Adopted.

The total attempt deadline includes preparation. An expired job enters Cancelling, marks its
completion unwanted and retains its attempt/input/ARC graph until actual worker retirement;
even an already completed, uncollected certificate cannot be adopted after that observed deadline. No retry
reuses a live input slot. A candidate queued within that deadline follows the existing separate
handoff/adoption turn. Explicit close joins before releasing nested input, captured history or
Services ownership, and never adopts uncollected work. Worker startup/admission and handoff
refusals preserve selected typed reasons. Native callbacks never execute preparation.

Completion checks: signed child through Preparing/Queued/Adopted, live endpoint polling during
preparation, exact timeout/cancellation and close in Preparing, guarded receiver retirement,
real command success/refusal/whole-run timeout, existing framing/session/loop contracts and
composite ownership lowering. RPC/UI lease behavior retains its independently tested contract.

Next: sustained network/load and cancellation responsiveness evidence, broader endpoint/bootstrap
configuration, persistent full/light stores and full state serialization/JAM parity. M1 framing
is complete; full serialization remains separate work.

## Local verification

On 2026-10-20, macOS arm64, pinned Nimony with checked ARC/Clang/LTO:

- `application_download_loop` passes signed Preparing/Queued/Adopted transitions, exact
  preparation deadlines, Cancelling retirement, close during preparation, LostPreparation,
  existing adoption refusal/ownership guards and native reception deadlines. A real unsolicited
  QUIC stream receives a native reset while the preparation lease is still active, proving
  endpoint polling precedes worker collection. Existing 1000-cycle ownership release passes.
- `application_block_download` passes raw asynchronous completion, completed cancellation,
  joined retirement and refusal of ordinary cancel/reception/enqueue while leased. Existing
  framing, real transport and 1000-cycle release checks pass. `application_download_session`
  retains its native callback/close and 1000-cycle release checks.
- `application_download_startup` passes real TLS command API adoption, identity/no-FIN/empty/
  preparation refusals and whole-run timeout; policy ownership release passes. The managed
  `application_preparation_lease` suite retains live UI and paused/resumed WebSocket coverage.
- Three private-field checks, three composite copy-lowering rejections, five strict runtime
  failures, two positive controls and both runtime-driver builds pass (15 guard verdicts).
- Production `make build`, application help/version, native harness (56), verification (35),
  inventory harness (11), formatting and changed documentation links pass. Inventory discovers
  234 native suites, 166 failure families and 2049 data-driven probes.

Evidence remains under `build/download-worker-*`. This establishes bounded worker integration
and lifecycle/network progress locally, not sustained load, a hard shutdown-time bound or canonical
Linux CI. Explicit shutdown can wait for non-preemptible execution to finish. Existing external
aliases still obey the exclusive borrow contract. No remote CI was requested.

## Signed worker reuse contract

The component workload reuses one stable raw receiver, Services owner and native worker for
100 fully received signed inputs: 50 genuine certificates queued and explicitly cancelled before
adoption, interleaved with 50 cancellations requested only after execution reaches Done. No early
cancellation can satisfy those completed-job iterations. An additional outstanding job is retired
by joined close without collection. Each iteration checks stale-ticket rejection, retained RPC
exclusion at Done, restored producer admission and idle handoff after collection, and unchanged
exact canonical parent. All captured graph aliases remain untouched during the lease.

Run `make unit SUITE=application_block_download`. The exact output contract includes
`WORKER_REUSE cycles=100 passed`, separate from the existing 1000 reception-only ARC cycles.
The worker workload does not assert exact `getOccupiedMem` equality: the pinned allocator defers
foreign-thread free accounting until the owning allocation class consumes its remote queue.
That host-only counter is not a complete worker-heap or process-memory measurement.

This is a component lifecycle/reuse workload, not sustained live-network load or a measurement of
running-PVM cancellation latency. Non-preemptible execution still governs joined shutdown time.
Next: sustained live-network load, independent memory observations and running-work responsiveness,
then broader bootstrap/endpoints and persistent full/light state. M1 framing remains complete;
full state serialization/JAM parity remains open.

Local verification on 2026-10-20 (macOS arm64, pinned Nimony, checked ARC/Clang/LTO):
`application_block_download` passes the 100-job reuse workload, existing exact framing/refusal,
real TLS transfer/deferred adoption, and 1000 reception-only ARC release checks. Formatting,
inventory discovery and whitespace checks pass. Production code and verification registries are
unchanged; existing production/guard evidence remains applicable to those identical sources.
Logs: `build/worker-soak-unit-final.log`, `build/worker-soak-final-format.log` and
`build/worker-soak-final-inventory.log`. Canonical Linux CI remains separate; no remote CI requested.

## Live download cancellation workload

The E2E plan owns `application_download_load`, a checked native driver with 32 authenticated,
fully received signed downloads against fresh TLS responders and one stable Services owner.
Each round reaches actual worker Done before an explicit attempt-deadline tick marks its output
unwanted. A real unsolicited server stream must receive a directional reset while the managed
lease is still held, before a later tick collects cancellation. Exhaustion must leave the exact
canonical parent unchanged and handoff idle; joined dispatcher cleanup restores admission.
A final fresh connection must queue and adopt a genuine child on separate host turns.

Completion requires exact native output `DOWNLOAD_LOAD cancelled=32 resets=32 adopted=1` and a
zero exit, with all fixture hashes checked before execution. E2E registration owns this verdict;
it is separate from native unit coverage. The normal entry point is `make check-e2e`.
Protocol/dependency/compiler pins and production behavior remain unchanged.

This workload proves repeated live reception, native progress during an uncollected graph lease,
completed-output cancellation and recovery. Its explicit protocol ticks are deadline stimuli,
not measured elapsed cancellation latency. It does not establish running-PVM preemption, a hard
shutdown bound, sustained concurrent traffic throughput or whole-process memory stability.
M1 framing is complete; full state serialization/JAM parity and persistent full/light stores
remain open. Next: independent memory observations and responsiveness under longer-running work.

Local verification on 2026-10-20, macOS arm64 with pinned checked ARC/Clang/LTO: the registered
E2E callable builds and passes all 32 cancellation/reset rounds and final adoption using production
crypto/Bandersnatch/QUIC libraries. Native pacing is flushed with bounded yielding responder turns
before the deadline stimulus; a tight zero-time flush is not treated as proof of packet delivery.
The exact marker and zero exit are retained in `build/download-load-e2e/results.json`; scoped setup
and execution logs are under `build/download-load-*`. Two adapter tests reject failed builds,
fixture changes, error exits and incomplete/extra/count-mismatched output. Four E2E-plan tests,
inventory discovery, formatting and whitespace checks pass. This is selected local E2E evidence;
other unchanged workloads retain prior evidence, and no remote CI was requested.

## Joined resource observations

Extend the same 32-cancellation/one-adoption E2E driver with an external gate after each round
returns. At these barriers all round-local transports, workers and captured snapshots have
retired; the same process and canonical Services owner stay alive. An independent OS observer
records 33 RSS/thread/descriptor samples before releasing the next round. Test-only gate files
are invocation-specific and have bounded waits. Failures always reap the child before writing
evidence. The exact ordered idle-marker transcript, final outcome marker and zero exit remain
required; missing or extra output cannot substitute for a successful native lifecycle.

Use the existing E2E soak budgets: sampled RSS below 256 MiB and at most two sampled active
threads, exactly one thread at every joined barrier, and post-warmup (eight rounds) RSS range
at most 16 MiB and descriptor range at most two. Retain all samples and sampled high-water
observations in `resources.json`. These finite OS observations include allocator/transport/native
library caches; they are not thread-local ARC accounting, proof of leak freedom, an exhaustive
peak sampler or a throughput comparison. Linux uses procfs, local macOS uses the existing ps/lsof
observer. Normal entry point remains `make check-e2e`.

The stack now includes merged PR #316. Worker and lease static dependencies are declared as
`fixtures: [state_report]` in their owning requirements; no central consumer registry is restored.
Protocol/runtime sources and pins remain unchanged. M1 framing is complete; full serialization,
JAM parity and persistent full/light stores remain open. Next: host responsiveness and cancellation
while a genuinely longer-running guest is executing.

Local verification on 2026-10-20, macOS arm64, pinned checked ARC/Clang/LTO and production native
libraries: the resource-observed E2E workload passes all 33 joined samples and the original
32 cancellation/reset rounds plus final adoption. After eight warmup rounds, sampled idle RSS
range is 327680 bytes (320 KiB), descriptor range is zero, and every idle thread count is one.
Five resource/adapter tests and four E2E-plan tests pass, including a parked-child timeout/reaping
witness and malformed/error-exit transcripts. Formatting, inventory and whitespace checks pass.
Evidence: `build/download-resources-e2e/results.json` and `download-load-work/resources.json`,
with scoped logs under `build/download-resources-*`. These are local finite observations, not
canonical Linux CI or a long-running memory guarantee. No remote CI was requested.

The #316 restack additionally passes 56 native harness tests, 13 fixture-contract tests and both
`application_preparation_worker` / `application_preparation_lease` native suites. Its unchanged
runtime-source and layer-patch checks are recorded in `build/pr316-restack-evidence.json`.

## Running preparation progress

A new independent fixture commits a single service's actual entry-5 static self-loop, its complete
code preimage and 40000000 gas allowance before signing the original parent and child. Explicit
trusted candidate round/step policies permit the loop to run until guest gas exhaustion; no sleep,
held thread or forged Running state enters production preparation. Before the existing resource
workload, one native round must observe Running, flush a real unsolicited TLS stream, enter
Cancelling at the explicit deadline and observe its native reset while the worker remains Running.
The graph/RPC lease stays held until actual Done collection. No expired candidate may publish.

The same signed loop is then downloaded again and must genuinely prepare, queue and adopt on a
later host turn. Canonical C(13) must identify service 42, no accumulated report digests and gas
consumption within one bounded block-pricing allowance (1000) of its 40000000 credit. A missing-code
skip or cheap panic cannot satisfy this positive control. The strict E2E transcript additionally requires
`DOWNLOAD_RUNNING resets=1 cancelled=1 adopted=1`. Existing short-job cancellation and 33 joined
resource observations remain required. Production code, pins and wire bytes are unchanged.
This demonstrates host/native progress during an observed Running preparation with a real busy
guest and recovery afterward; it is not guest preemption or a hard cancellation/shutdown-time
bound. M1 framing remains complete; full serialization/JAM parity and persistent full/light stores
remain open. Next: broader bootstrap/endpoints and durable state integration.

Local verification on 2026-10-20, macOS arm64 with pinned checked ARC/Clang/LTO and production native
libraries: the registered E2E workload passes Running-before-deadline and Running-after-native-reset
assertions, exact cancellation with unchanged canonical parent, and positive adoption with the
near-full-credit C(13) gas check. C(13)'s accumulation count denotes accumulated report digests;
it is zero for this allowance-only fixture, while its nonzero gas row certifies actual execution.
The original 32 short-job cancellation/reset rounds, final adoption and all 33 joined resource
observations remain passing (post-warmup idle RSS range 114688 bytes, descriptor range zero,
idle threads one). Evidence is `build/running-download-e2e/results.json` and the logs under
`build/running-download-*`. Five adapter/resource tests, including rejection of the old transcript
without the Running marker, plus four E2E-plan tests, formatting, inventory and whitespace checks
pass. No remote CI was requested; Linux CI remains separate from this selected local run.
