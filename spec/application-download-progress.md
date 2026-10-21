# Bounded successive child downloads

## Scope and authority

Extend the merged one-child command and explicit ancestor inputs to a finite
operator-selected number of successive children. Reuse GP 0.8.0 revision
`07f041dabd073f9018b418e9ee72e79dd2185401` and vectors
`d3c089c9a1d5352ad353626d7a2db8589f137b2a` without protocol/pin changes. Existing
admission, finalized execution, exact-parent composition and durable receipt
owners remain the sole authorities for adoption. Preserve explicit pinned peers,
checkpoint trust, bounded history and explicit finality.

## Lifetimes and intended progression

One `receiveChildren` activation keeps stable authenticated endpoints and one
Services owner for the complete run. `BlockDownloadLoop.nextChild` rearms only
after a genuine consumed adoption, native stream close, input retirement and
worker/publication lease release. Refusals preserve the prior adoption diagnostic
and ancestry. All graph/ancestry replacement happens on the host between jobs;
final shutdown joins before outer canonical inspection or alias retirement.

`--download-blocks COUNT` is download-only, defaults to one and accepts canonical
positive decimal values 1–64. Before file/Services IO reserve initial ancestors
plus `COUNT-1` older headers and one additional selected parent in report policy.
Actual per-header/input/report bytes are checked again before each new child.
Never drop old headers to make a quota fit. Each adopted parent's sealed header
is prepended newest-first for the next child; no history/state is fabricated.

Retry/stage budgets restart explicitly per child on the same monotonic clock.
One shared run deadline starts after Services startup and is checked between
bounded dispatcher turns; successful children never reset it. No new handshake
or connection slot is consumed per child. Existing finality, checkpoint trust,
exact-parent authority and memory/disk receipt rules remain unchanged.

`runDownloads` returns immutable scalar requested/adopted counts plus a terminal
reason; the old `runDownload` status-only API remains. Count only consumed genuine
adoptions. After joined teardown also reconcile the one possible outstanding
durable receipt against the actual canonical child. A timeout can therefore
report confirmed progress while retaining its Timeout reason. These diagnostics
are not execution certificates. Every later refusal preserves the confirmed
prefix. No fork choice, automatic finality, discovery, partial light-map claim or
storage-maintenance adoption is introduced.

## Completion witnesses

Preserve all one-child scenarios first. Add canonical bounded options and exact
progress reporting; real successive signed blocks and full-map manual parity;
updated CE requests; report lookup context; wrong-parent/stale/invalid second
children; shared deadline and clean cancellation; RPC head/history observation;
normal disk restart and later failure preserving the confirmed prefix. Exercise
quota arithmetic before IO and dynamic byte limits before the next request.
Require runtime/privacy guards where new public results need them and fresh ARC
ownership evidence. Keep logs in ignored `build/multiblock-*` files.

M1 framing remains complete; full state serialization and whole-block JAM/STF
parity remain open. Managed storage remains owned by db #1.

## Child-lifetime verification

The refactored command passes the existing startup suite: all original and
lookup-backed TLS/disk scenarios, pre-transport refusal, shared parser behavior
and joined shutdown remain required. Its separate 1,000-cycle policy observation
retains 788,448 occupied bytes before/after. Pinned semantic compilation and
whitespace checks pass. Evidence uses `build/multiblock-refactor-*`.

## Genuine successive-chain fixture

A separate test-only fixture derives three genuine signed children from each
previous composed complete map. Later seals/entropy proofs bind the actual
selected parent hash, complete root, slot and parent entropy; the authored fixture
stays before its epoch/tail boundary. It never mints execution certificates.
Independent re-execution matches every serialized entry and root at each step,
retains parent history, refuses stale replay and leaves finality unset. CE128
requests are spelled independently and change with every selected parent.

The earlier one-child fixture's validator-statistics decoding budget permits one
prior service row; execution produces two. Successive fixtures explicitly allow
four prior rows without changing legacy defaults or production policy. The
focused native chain suite passes with unchanged 312,160 occupied bytes across
1,000 complete three-child execution/composition/refusal cycles. Semantic checks,
source-owned inventory and whitespace checks pass; logs use
`build/multiblock-chain-*`. This is local evidence, separate from Linux CI and
complete block/epoch parity.

## Bounded command and rearming verification

Real pinned-TLS runs adopt one, two and three genuine children. Independent
responders verify every changed CE128 parent request, observing exactly the
requested count over retained authenticated connections. Insufficient whole-run
ancestry count refuses before fresh disk creation. All 64 admitted count values,
default one, malformed/full-width/duplicate counts, disabled/unrelated commands
and four raw-field privacy rejections pass. Failed/default outcomes expose only
zero scalar progress.

The loop suite additionally checks active-worker refusal, backwards clock and
invalid replacement ancestry preserving the prior receipt, explicit rearming
without publication, and repeated Waiting refusal. Its 1,000-cycle observation
retains 159,584 occupied bytes. Existing TLS/startup/lookup/disk scenarios pass
with their separate policy observation at 787,648 bytes unchanged. Evidence uses
`build/multiblock-{progress,options,loop,startup-regression}*`.

Affected legacy app/ancestor/recovery parser suites and the actual executable
build pass. The executable keeps the original single-child success/failure tokens
and adds `DOWNLOAD_PROGRESS adopted=N requested=M` for multi-child requests.
The confirmed count includes only actual consumed receipts or the one joined
shutdown receipt; it never counts attempted/downloaded bytes. Semantic, privacy,
inventory and whitespace checks pass. Remote CI remains unrequested.

## Later-child failure and retry witnesses

The expanded real TLS suite passes one/two/three/eight-child runs, then verifies
that an empty response, stale first-child replay, damaged second seal, malformed
second block and a tight evolved-statistics composition policy each report one
confirmed adoption out of three requested children. Every negative responder sees
the actual second parent-bound request. A one-byte-short accumulated ancestry
budget reports two adoptions and sends no third request; the exact byte ceiling
permits all three. No resource refusal silently drops an ancestor.

A missing second FIN reaches the shared 4,000 ms command deadline before the
explicit 20,000 ms stream/30,000 ms attempt ceilings, preserving one adoption and
two observed requests. A two-pin empty-first fallback consumes exactly three
requests at each independent identity while adopting three children, proving that
each rearmed child gets its explicit fresh attempt policy on retained endpoints.
The shared exchange helper joins every responder after command workers/callbacks
retire. Pinned semantic and native checks pass; evidence uses
`build/multiblock-prefix-*`. Scalar prefix observations are followed by direct
RPC/durable-map verification in subsequent layers.

## Independent live RPC observation

A forked RPC client subscribes to the actual command listener before the responder
releases child one. It receives the initial head and exactly three ordered genuine
adoption notifications. Before a gated fourth empty response can end the command,
it queries every retained block's independently expected state root, exact sealed
header and parent, plus current best head and unavailable finality. The next
ordinary reply also proves no duplicate notification displaced the response.

The final empty response yields Exhausted with three confirmed adoptions from
four requests. The independent TLS responder observes four exact parent-bound
requests; all child processes join and the RPC port is released. Response gates
exist only in test responders and perform no callback file IO or production
fault injection. Pinned semantic and native `application_download_rpc` checks
pass; evidence uses `build/multiblock-rpc-*`.
