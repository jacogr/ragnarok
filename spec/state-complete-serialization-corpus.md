# Independent complete typed serialization corpus

Scope: Gray Paper pin `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d`, existing
single C13 compact-gas interpretation and unchanged local V1 checkpoint envelope.
This authored corpus qualifies serialization, not protocol admissibility or STF execution.

Thirty-two complete maps include all sixteen exact global chapters and fully typed
service metadata, raw storage, preimage content and matching request identities.
Inputs vary time, full-width metadata and service IDs, all four request history
modes, empty raw keys/values/content, and 31/32/33- and 63/64/65-byte boundaries.
The Python reference constructs mapping keys and complete sorted envelope bytes
using independent byte equations and a list-partition trie. Native code builds
typed fields, composes the complete map and compares every checkpoint byte; it
then restores the independently supplied checkpoint under its expected root and
exact service declarations. No opaque captures supply a service identity.

The SHA-pinned fixture reproduces using
`python3 tests/state_complete_serialization_oracle.py`; Python reference tests
check authored envelope anchors and deterministic reproduction. Run
`make unit SUITE=state_complete_serialization` for the native comparison.

The global chapter shapes reuse the existing independent composition fixture;
only time varies here. These are authored current-schema witnesses, not a new
published current-pin corpus. Cross-chapter validity, whole-block STF evidence,
root discovery, runtime adoption, Services and storage formats remain separate.

Observed locally on macOS ARM64 with pinned checked ARC/Clang release: all 32
native cases, three independent Python checks, source-owned verification inventory
and pinned Nim/Rust formatting passed. Exact-head Linux CI remains separate.
