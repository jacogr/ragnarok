# Consecutive current block fixture

Authority remains Gray Paper `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d`.
A bounded test-only fixture authors each subsequent ordinary in-epoch child from the actual
preceding current successor: full sealed parent hash, posterior map commitment as prior-state
field, next slot, exact empty extrinsic commitment and genuine seal/entropy proofs. Existing
synthetic signing keys and implemented release-reference VRF profile remain explicit; this
cannot establish current Thin VRF or published full-block STF parity.

Expected successors follow individually invoked authenticated admission, reports, queue/round,
current completion and guarded chain capture/install. The candidate adapter is checked separately
against each complete expected map. This gives independently authored wire/phase-order witnesses,
not an independent reimplementation or upstream posterior golden. Resources are caller-authored;
the new test policy permits up to four statistics rows without altering old fixtures. The plain
continuation also fits the original statistics cap; a separate C3 cap witnesses later refusal.

Completion requires at least two consecutive genuine successes, every map entry/head identity,
prior/posterior linkage, exact retained history, stable historical aliases and refused replay.
Run `make unit SUITE=pvm_current_consecutive_fixture`. No producer, runtime or pin change is planned.
M1 framing remains separate from full state serialization and full JAM parity.

Local macOS checked ARC/Clang validation passed: three consecutive current successors, every
map entry and retained head, prior/posterior linkage, unchanged original aliases and replay
refusal; focused semantic checking, inventory and pinned formatting. No runtime source changed.
