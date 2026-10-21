# Computed guarantees included in their authenticated candidate

Pins: GP 0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401`,
reporting_assurance.tex guaranteesextrinsic; header.tex extrinsic commitment;
serialization.tex guarantees. Vectors remain
`d3c089c9a1d5352ad353626d7a2db8589f137b2a`.

Consume only a completed ComputedGuaranteeBatch. Derive the original successful
post-assurance coordinator from its retained first source, whose authority is
shared by every batch input. Require exact cardinality and byte-for-byte equality
between the batch's canonical guarantee sequence and that coordinator's own
admitted candidate guarantee component, including every report, slot, index and
signature. Counts and complete extents precede independent bounded wire copies.
Retain the batch and genuine stage only after complete equality. No detached
candidate or caller-supplied transition is accepted. Defaults/refusals retain no
payload. Getters share immutable authority and return the original component.
No hashing, signing, verification or publication takes place.

Completion plan: author a real guarantee-bearing candidate, recompute its
extrinsic commitment and real seal, execute its prefix from the exact original
snapshot and rebind original computations/verify credentials to that actual
candidate. Test exact inclusion, missing/changed guarantees, defaults, exact/
short wire policies, source/stage identity, copied bytes/lifetime, zero new hashes,
1000-cycle ARC, strict runtime extraction and compiler privacy/source guards.
Regress shared batch fixture consumers and merged discovery/provenance checks.

Next: integrate source-bound included computations with existing report policy
and admission without accepting mutable observation tuples. Inclusion is not
full report admission, availability or finality. M1 framing is complete; full
state serialization remains open.

Local evidence: checked optimized macOS ARM64 `pvm_computed_inclusion` passes
with exact candidate-component/source-batch bytes, real body commitment/seal,
completed prefix and independently reverified computed credentials. Missing
candidate guarantees and a canonical one-byte signature change refuse inclusion.
Exact/short caps, private stage-copy mutation, detached lifetime and zero-new-
hash tests pass. Fresh1000-cycle ARC is292320/292320. Existing batch consumer
passes unchanged286256/286256 after shared config extraction. Seven strict
optimized runtime probes, four exact compiler rejections,35 verification-harness
tests, inventory, formatted unit/driver semantic checks and pinned formatting
pass. Evidence: build/computed-inclusion-*. Exact-head Linux CI remains separate.
