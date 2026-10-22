# Parallel accumulation conflict annulment

Authority: Gray Paper `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d`,
accumulation.tex eq:accpar, `acc(s)` and `N(o)`. Prepare a pure bounded certificate
from genuine normalized outcomes belonging to the same input owner and complete
prior snapshot. This layer does not enable foreign account publication.

Resolve each invoker's effective supervisor from the common prior, including the
supervisor incarnation check and missing-nominee fallback. Annul an outcome only
when its own modified set contains the invoker, the original supervisor outcome's
modified set also contains that invoker, and the effective supervisor differs from
the invoker. Evaluate every decision against original outcomes, never recursively
against already annulled decisions. Missing supervisor execution means identity.

The selected account state of an annulled outcome is the complete prior state.
Its selected modification count, outgoing-transfer count and yield presence are
zero. Actual gas and provisions remain attached to the original genuine source.
Keep original outcome extraction explicitly named; it is not a selected-context
substitute. No mutable or caller-authored decision can construct a certificate.

Bound source count, total modified entries and every metadata/membership predicate
before work. Refuse default outcomes, disabled tracking, unrelated provenance,
duplicates, malformed metadata, limits and invalid full-width ordinals without
exposing a partial certificate. Tests must cover conflicting writes, untouched
juniors, self/stale/missing supervision, execution order, exceptional checkpoints,
retained gas/provisions, no hash work, ownership and checked result guards.

## Local verification (2026-10-22)

The source-owned native suite passes with fresh1,000-cycle ARC release evidence.
Actual guests prove simultaneous mutual conflicts, execution-order independence,
prior supervision after a successful handoff, untouched juniors, incoming-credit
membership, self/stale/missing nominees and exceptional checkpoint selection.
Annulled selected observations restore the exact prior map and clear modification,
transfer and yield observations while retaining original gas and provisions.
Malformed nominee metadata, unrelated input/map owners, disabled capture,
duplicate/default outcomes, exact independent work limits and upper-half ordinals
refuse without candidate state. Preparation performs no state hashes.

All267 production modules,9 strict runtime extraction guards,5 compiler
privacy/nominal rejections and54 focused failure/verification harness tests pass.
Inventory, formatting and diff checks pass. Evidence remains under
`build/parallel-annulment-*` and `build/tests/parallel-annulment-*`.
These are local checked macOS ARC/Clang observations, separate from Linux CI.

Next: bind account selection and terminal projections to these decisions before
removing any foreign publication gate. The certificate deliberately retains the
original outcome through an explicitly named accessor for gas/provision provenance;
it does not expose a fabricated selected effect context or claim complete accpar
publication. No protocol discrepancy or pin change is introduced.

## Common invocation frame extension

The [skipped-credit adapter](pvm-skipped-credit-selection.md) adds checked common
bootstrap slot/entropy agreement and guarded input/slot provenance. A genuine
empty executed source exposes NoInvocationSlot, distinct from a real invocation
at slot0. These are source-coherence checks, not authenticated block/header proof.
