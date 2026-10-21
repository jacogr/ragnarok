# Accumulation supervisor host

## Scope and authority

Implement current Gray Paper `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d`,
`pvm_invocations.tex` Omega_V (supervisor29), `accounts.tex` effective-supervisor
equation and `definitions.tex` CgasV=1000. Existing source hashes are in `pins.json`;
no dependency or specification pin changes.

Charge1000 before reading either selector. Registers7/8 select the target and new
supervisor; either all-ones sentinel means the invoking service. Preserve full-width
IDs until WHO checks. Both accounts must exist before authority is checked. Only
the target's effective supervisor may reassign it: designation is effective only
when the designated account exists with the recorded creation slot, otherwise the
target supervises itself. Refused authority returns HUH, not a fabricated success.

Success returns OK and atomically replaces only target supervisor ID and creation
slot with the selected current account's identity. Preserve balances, code, gas,
storage, timestamps, current execution and both retained checkpoint dimensions.
Local malformed/backend/store refusals expose no partial successor.

Self metadata uses the existing publication proof. Foreign mutation retains the
explicit Unsupported account scope until parallel modified-account conflict
selection is implemented. Later self mutation or identical-byte restoration cannot
relabel foreign ancestry. This is not full parallel accumulation or whole-JAM parity.

## Completion checks

Native supervisor witnesses cover exact/short gas, self sentinels, full-width IDs,
missing target/nominee, authority versus existence, stale/missing supervisor fallback,
reassignment and lost authority, immutable retained maps/checkpoints, exact encoded
metadata, atomic backend/write refusal and1000-cycle ARC release. Verify self
publication and foreign publication refusal in a genuine common-source batch.
Run affected effect/dispatch/upgrade/batch consumers and strict failed-result and
nominal API guards, retaining source-owned harness/inventory checks.

## Local verification

On macOS the supervisor, account-publication, upgrade, effects, dispatch and batch
native suites passed with stable1000-cycle ARC evidence. Both self and foreign
supervisor transitions are released in each supervisor-suite cycle. All264
production modules passed semantic compilation. Compiler rejection guards, including
the observed AccountSlot-versus-ServiceIndex diagnostic, and40 strict accumulation
effect result probes passed. Python discovery passed639 tests with three existing
documented gates. Pinned formatting and inventory checks passed.

The common-source publication fixture uses a plain companion halt, isolating these
metadata changes from unrelated preimage provisions. Self metadata publishes and
retains all unrelated entries; selected foreign reassignment refuses publication and
retains the original root. These are local results, not exact-head Linux CI, full
parallel accumulation or complete JAM parity. Evidence is under `build/supervisor-*`
and `build/tests/supervisor-guards/results.json`.
