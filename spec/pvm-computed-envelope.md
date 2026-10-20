# Canonical computed guarantee envelopes and reporter keys

Pins: GP 0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401`,
C.2 standalone guarantee serialization and reporting_assurance.tex reporters set.
Vectors remain `d3c089c9a1d5352ad353626d7a2db8589f137b2a`.

Scope: consume only CredentialedComputedReport and independent report-copy,
whole-guarantee byte and unique-reporter ceilings. Derive original complete report,
configured core/structural validator ceiling, verified evaluation slot and fixed
credentials through its retained provenance. Prove native/wire size bounds before
variable allocation, re-query authenticated selected keys and form a canonical
lexicographically sorted unique Ed25519 reporter set. Deduplicate by full key bytes,
not credential indices or signature occurrences, before applying reporter budget.

Capture an immutable OwnedReport from the exact original report bytes, retiring
the temporary copy before encoding; use existing canonical measure/encodeGuarantee
APIs under the original configured core count and 3*cores validator ceiling. A
previous-rotation credential index may exceed current population and remain valid.
Retain original certificate, complete Guarantee value, canonical standalone wire
and fixed reporter set only after full success. Wire is report || E4(slot) ||
one-byte canonical credential count || ordered E2(index)/64-byte signature pairs;
there is no outer extrinsic sequence count. Copies/getters cannot replace source.
No report rehashing, signature verification, signing, execution or publication.

Each byte ceiling bounds its corresponding complete serialized copy/encoding;
report and guarantee policies are separate, not an allocator-overhead measurement.
The original source already retains its own immutable report. New capture holds
an independent report copy; temporary source bytes retire before guarantee-wire
allocation. Fixed at-most-three reporter/credential arrays need no variable budget.

Completion plan: real current pair/triple and prior9/current6 source certificates;
independent explicit standalone wire assembly and exact codec decode/re-encode;
original report/slot/signature identity; exact/short report/guarantee/reporter limits;
lexicographic reporter key order and genuine repeated-key credentials; no new hashes
under refusal; copied wire/Guarantee/metadata/key mutation, detached lifetime and
1000-cycle ARC release; strict runtime/compiler guards. Extend shared fixture only
through default-preserving optional active-key repetition; run its old consumer.

Next: source-bound report-policy/admission integration or bounded multi-guarantee
composition. Report inclusion, complete transition-policy/chainspec equivalence,
exporter trust, availability/finality and signing remain open. M1 framing is complete;
full state serialization and whole-block parity remain open.

Local evidence: checked optimized macOS ARM64 `make unit
SUITE=pvm_computed_envelope` passes genuine original computation, authenticated
posterior assignments and verified current pairs/triples plus previous-rotation
credentials. Explicit independent byte assembly equals complete standalone output;
canonical decode consumes all bytes and re-encoding reproduces them. Report prefix,
E4 slot, E2 indices and every signature byte remain exact. Previous 9 indices 7/8
survive encoding under original configured three-core/nine-validator ceiling while
the current active population is six.

Independent OpenSSL Ed25519 seed-import public-key references prove credentials
ordered by seeds 11/14/15 yield reporter order 14/11/15. An originally committed,
genuinely signed active roster repeats seed 12 identity at distinct credential
indices 1/2; both real signatures verify, both credentials remain in canonical wire,
and one reporter budget suffices. Reporter ordinal 1 is correctly absent in that
set. Exact report/wire/unique-set limits pass, independently one-byte-short or
one-key-short policies refuse. Failed/default sources/results/accessors and large
reporter ordinals retain typed refusal. Copied wire, Guarantee report/credential/
slot, metadata and keys cannot replace the retained owner. Detached source/output
lifetimes and exact original complete-map provenance pass.

Materialization and reporter queries attempt zero hashes under actual Blake2b
backend refusal. Fresh warmed 1000-cycle ARC occupancy is 339232/339232 bytes,
including repeated-key success, independent output copies and reporter-policy
refusal. The old default roster fixture consumer freshly passes unchanged
320176/320176 ARC occupancy. Eleven strict optimized extraction probes and seven
compiler privacy/source/ordinal guards pass with genuine controls; formatted
semantic checks, inventory, 20 affected tooling tests and pinned formatting pass.
Only the default-preserving optional test fixture changes among prior inputs;
lower production modules and all specification/toolchain pins are unchanged.
Remote CI has not been requested.
