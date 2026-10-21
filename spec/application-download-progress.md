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

Each child runs in a separate `receiveChild` activation. Its stable dispatcher
and every stream/input/preparation/disk-publication alias retire only after joined
teardown, before the caller inspects the next canonical head or mutates its local
ancestor sequence. One Services instance outlives the complete run. A shared
monotonic deadline covers every child; retry/stage policies remain explicit.

The follow-up progression will count only consumed successful adoption receipts,
retain the prior selected header newest-first for the next child, and bound total
requested work and accumulated ancestry without silently dropping old headers.
Later failure preserves earlier confirmed publications. No fork choice, automatic
finality, discovery, partial light-map claim or storage-maintenance adoption is
introduced.

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
