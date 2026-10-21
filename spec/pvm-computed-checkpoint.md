# Computed checkpoint storage selection reaches canonical state

Pins: GP0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401`,
pvm_invocations.tex checkpoint (18), Y'=X, and write (5), with accounts.tex
footprint rules; vectors `d3c089c9a1d5352ad353626d7a2db8589f137b2a`.

Author both programs before original roots, signing and computation. Write
key[11]/value[21,22,23], checkpoint the complete regular implication, then write
the shorter value[22,23] to that same key. Halt must select the later regular
value with 37 footprint bytes; panic must select the earlier exceptional value
with 38 bytes. The existing uncheckpointed panic remains an absent-row control.
Original balance50 admits both writes. One provenance key must handle the same
key twice, and the final byte limit must apply to the selected value.

Completion: genuine compute/sign/admit/execute/stop/finalize/compose/publish
through all five storage modes; actual termination/dimension, both host writes
and checkpoint charged, selected context/final/prepared/canonical/head values
and footprint agree; activity and original parent aliases remain coherent;
replay refuses, detached checkpointed child and 1000-cycle ownership pass.
Use maintained semantic/resource limits without widening them for this witness.

Next: exercise checkpoint selection after guest out-of-gas through the same
computed state and canonical chain publication path. M1 framing complete; full
serialization, whole-block parity and full chainspec equivalence remain open.

Observed local evidence: the genuine checkpoint/halt program publishes the later
two-byte value and 37-byte footprint. The checkpoint/panic program publishes the
first three-byte value and 38-byte footprint through selected outcome, stopped
finalization, composition, canonical store and best-head state. Both guest write
costs and checkpoint cost are included in actual charged gas, and C(13) retains
two refinements, one accumulation and that same actual gas. All original storage
controls, local-budget refusals, parent aliases, metadata, finality and replay
checks remain covered. No protocol or independent resource limits changed.

The five-mode suite passes with ARC unchanged at 2211440/2211440 bytes over
1000 cycles, each publishing all five prepared outcomes. The existing default
chain suite also passes (1079904/1079904 bytes, 1000 cycles), together with 28
optimized chain runtime guards, inventory and pinned formatting. Previous
compiler guards remain valid for 1703 unchanged production/native/compiler-
fixture/toolchain inputs. Verification tooling and registrations are unchanged.
These are local macOS checked-release results; remote CI was not requested.
