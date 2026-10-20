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
