# Dependent register chains across blocks and host continuations

## Scope and planned checks

Gray Paper 0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401` remains primary;
PolkaVM `69e5b87c9888bc4f94cabdadc9661cf68a1bfbfa` is the public interpreted
cross-check. Pins, production code and scoped discrepancy decisions are unchanged.

Add original deterministic programs containing each of the 85 register opcodes,
with prior destinations feeding subsequent sources. Vary ordering, input bit
patterns, immediates and aliased operands. Put a host checkpoint after each mutation
and a fallthrough terminator after each group of seventeen operations; finish with
trap. Independently derive every thirteen-register checkpoint and each block's
pipeline price/cycle count. Both engines must retain exact/surplus success and
completed prefixes when each successive block is one gas unit short.

Freeze inputs with a content descriptor; runtime checks never regenerate them.
The public Rust engine and native host-aware executor consume identical code and
expected checkpoints. Require full register files, host PCs, gas, callback counts,
terminal outcomes and native source preservation. Independently verify fixture
reproduction, opcode coverage and known arithmetic edges before integration.
This deterministic fixture expansion is not the complete upstream fuzzing job.

## Observed evidence

The frozen corpus contains eight distinct opcode orders, 680 independently derived
full-register checkpoints and forty block-price/cycle pairs. Each program passes
surplus/exact completion and five one-short block entries: 56 scenarios and 2,720
validated host callbacks across the corpus. Both pinned public interpreted PolkaVM
and checked native execution match every register, callback PC and gas observation.
The native consumer additionally preserves its original machine aliases and checks
each exact/one-less gas simulation limit. Final trap is PolkaVM `Trap` and native
recursive `Panic`; the native boundary normalizes final PC to zero as specified.

The supported integrated Make target passes all fifteen discovered reference/native
pairs. Three independent Python model/provenance tests and eleven runner/summary
controls pass; inventory, pinned formatting and diff whitespace checks pass. Both
real consumers accept an unchanged positive input and reject changed checkpoint
registers, a changed checkpoint count and truncation. These are local macOS checked
ARC/Clang LTO and pinned Rust observations; no Linux run is claimed for this layer.
Production source, benchmark fixtures and all pins are unchanged.

Raw integrated evidence is retained locally under
`build/pvm-register-chain-evidence/`; mutation controls and complete diagnostics are
under `build/pvm-register-chain-controls/`. Reproduce with
`make unit SUITE=pvm_register_chain_reference` and `make check-pvm-reference`.
Fixture regeneration is explicit `python3 tests/pvm_register_chain_reference.py`;
ordinary verification checks the frozen bytes and never rewrites them.

Further composition still includes loops, mixed memory and richer host transitions;
these straight-line arithmetic/fallthrough chains complement the existing mixed
loop matrix. They do not establish arbitrary-program equivalence or satisfy the
separate complete upstream differential fuzzing obligation.

The unchanged frozen scalar/chain oracles now qualify complete invocation policies and both
callback forms; see [register policy reference](pvm-register-policy-reference.md).
