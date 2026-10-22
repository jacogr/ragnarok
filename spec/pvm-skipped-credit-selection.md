# Certified skipped credits in prior-account selection

Authority: Gray Paper `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d`,
Psi_A's code-unavailable alternative after incoming transfer credit, fnpartitionxfers
and accpar M(s). Extend the bounded account selector with explicit genuine
SkippedAccumulation owners. A skipped invocation is not a fabricated executed
AccumulationOutcome; its zero-gas/no-yield/no-output proof and exact post-credit
snapshot remain distinct.

Validate every supplied skip against the annulment certificate's exact input/prior
owners, reject duplicate executed/skipped IDs, and bind invocation slots. Executed
annulment sources must also share their bootstrap slot and entropy; empty executed
source has a typed missing-slot observation. Independent skip count/native extent
and predicate work limits precede capture. Old no-skip calls retain their scope.

Every skipped recipient with incoming records, including zero-amount records,
marks its own account and selects its exact credited skipState. Require a different
effective prior supervisor to be absent from all active input groups: otherwise
those transfers were not safely partitioned and preparation refuses without state.
A skipped supervisor cannot alter another logical account, so prior identity is
sufficient there. An uncredited skipped junior still yields to an executing prior
supervisor, including selected deletion.

Expose copied skipped origin/count observations and a guarded genuine skip getter.
Executed-outcome extraction from a skipped origin has a typed refusal. Preserve
all default/failed payload guards, copied metadata ownership and no-hash behavior.
Tests cover missing code, actual liquid/protected/zero credits, safe versus unsafe
input groups, frame/provenance/duplicate/cap refusals, parent precedence, release
ownership and fresh ARC evidence. Complete coverage/publication remain gated.

The exact [pinned Psi_A alternatives](https://github.com/gavofyork/graypaper/blob/1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d/text/pvm_invocations.tex#L147-L179)
retain the post-transfer state and incoming-recipient modification set when code
is unavailable. Common bootstrap slot/entropy checks establish agreement among
supplied invocations, not authenticated header/posterior-entropy provenance; the
existing completed-round adapters retain that higher-level obligation.

## Local verification (2026-10-22)

The new source-owned suite and4 affected annulment/account/transfer/yield
consumers pass with fresh1,000-cycle ARC evidence. Real missing-code preparation
covers liquid, protected and zero credits, matching inactive/missing/stale
supervisors, unsafe active-supervisor exclusion, skip-only frames, selected parent
deletion and skipped-supervisor identity for another logical account. Genuine
executed outcomes with different bootstrap time or entropy refuse; real slot0
remains distinct from initialized empty-source NoInvocationSlot. Input/map owner,
duplicate/default skip and exact independent cap refusals are covered without
new state hashes. Selected skipped state survives caller release and exposes
NoExecution rather than a fabricated interpreter outcome.

All269 production modules,20 strict runtime result guards,13 compiler
privacy/nominal checks and54 focused harness tests pass. Inventory, formatting
and diff checks pass. Evidence remains under `build/skipped-credit-selection-*`
and `build/tests/skipped-credit-selection-*`. These are local checked macOS
ARC/Clang observations, separate from Linux CI and complete JAM interoperability.

Next: global role/creation/physical-write selection and complete batch integration.
This layer handles certified unavailable-code accounts; Psi_A's absent-account
alternative remains a separate no-credit/no-execution source obligation before
claiming complete current-round interoperability. No foreign publication gate is
removed by this feature.
