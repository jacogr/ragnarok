# Current-bound supplied logical parent description

Scope: retain the exact physical parent description and original current profile/full-Parameters
provenance together for future handoff. Pins remain Gray Paper
`1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d` and vectors
`d3c089c9a1d5352ad353626d7a2db8589f137b2a`.

`captureCurrentLogicalState` accepts only an initialized `CurrentStateSerialization`, stable borrowed
full service declarations and explicit supplied-logical limits. It revalidates the raw-key companion
against the original current compact inventory's manifest. It accepts neither a separately captured
raw-key owner nor an equal-root replacement snapshot. Success privately retains both the original
current owner (including original profile/full Parameters) and the new supplied logical owner.

The companion has its own freshly revalidated compact inventory: it shares the exact physical snapshot
identity with the original current inventory, not the compact inventory identity. Consumers must keep
these two meanings distinct and never join same-inventory predicate certificates across the captures.
Full matching and raw-key resource refusal retain the original guarded nested stage; default and
failed owners expose no parent prefix. Detached supplied-service reconstruction is available from
the companion under its own explicit descriptor/payload budget without hashing.

This is a supplied-and-validated parent description. No producer export, selected execution delta
propagation, service creation/deletion/rollback maintenance, full semantic/STF qualification or new
root/installation/finality authority is implemented. Future producer integration must start from this
exact physical parent and account for every namespace mutation, retaining untouched raw keys.

Creation, retain/copy/drop and projection share canonical ARC host ownership and must run before proof
enqueue or after collection/join. No worker, Services, RPC, storage or producer interface changes.
Verification covers actual signed ordinary/disputed/ticketed/epoch complete authored successors,
exact original physical/full-parameter identity, distinct compact captures, mutated/omitted declarations,
prehash extra-resource refusal, hash-free source/projection queries, strict runtime/compiler guards
and 1,000 ARC cycles.

Observed locally: native cases and 1,000 ARC cycles passed at 1,693,552 bytes before/after;
five strict runtime and seven exact compiler guards with signed positive control passed.
Inventory and pinned formatting passed on macOS ARM64 checked ARC/Clang release. Linux CI is separate.
