# Current external-publication handoff

Pinned Gray Paper `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d` remains unchanged.
This adapter adds no protocol semantics, pins, storage format or native worker transitions.

The current handoff can mark its Pending update Publishing before an external publication lease.
It retains the exact immutable expected update without exposing it through the Pending accessor.
Publishing remains Busy, cannot be cancelled, and ordinary canonical/RPC processing does nothing.
The host must freeze all aliases throughout external borrowing and call completion/refusal only
after collection or joined close retires those borrows.

`completePublication` accepts an actual guarded application installation result. Success must match
the expected sealed child hash, exact state identity and complete parameter tuple. Equal roots/hashes
with a different state owner refuse. Failed/default installation results become DurabilityRefused.
Explicit stale/RPC/durability refusals are terminal before or after external entry, never rollback
promises. Every success/refusal occupies Finished until acknowledgment. No method hashes, executes,
performs IO or installs state.

This host bookkeeping certifies the exact installed child, not a successful disk operation. The
Services disk consumer must separately retain an actual successful IO receipt and confirm the exact
selected disk generation/state/context before installation; uncertainty remains in its original
storage result. That consumer is subsequent work. Existing memory handoff and Services behavior
remain unchanged until they select the new phase.

Completion witnesses cover all phase/cancel/backpressure transitions, host installation success,
pre/post-entry typed refusal, default failed installation, equal-root/equal-hash foreign state receipt,
no-hash bookkeeping and 1,000 ARC cycles. Source-owned phase guards, prior extraction/privacy/
nominal contracts and current memory/Services regressions remain required. These deterministic
host transitions add no concurrency hypothesis needing a model. Local macOS evidence remains
separate from Linux CI and full JAM/production transport/durability parity.

Local macOS ARC/Clang validation passed: the new external-publication and existing current memory
handoff native suites (fresh 1,000-cycle ARC evidence each), current Services memory/RPC regression,
five exact runtime phase/extraction guards, privacy and exact legacy/current call-position rejection,
four affected consumer semantic checks, inventory and changed-source formatter idempotence.
The older nominal fixture's metadata now matches the observed pinned call/argument diagnostic.
Linked checks were serial. Exact-head Linux CI has not been requested.
