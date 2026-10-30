# Owned execution-frame page images

## Scope and ownership

This local memory-setup change follows dirty-page checkpoints. Gray Paper
`1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d`, dependency pins, memory permissions/fault ordering,
source PCs, gas, attempts and native code ABIs remain unchanged.

`MachineResult.takeValue` transfers a successful owned payload and consumes the result's success
state. The existing `value` accessor still returns a copy. No mutable view of immutable Memory
storage is introduced: `memoryImages` first constructs independent caller-owned page images.

The private frame builder consumes one admitted image sequence after copying accessible bytes
into resident regions. It transfers the sequence into `sourceImages`, including inaccessible
pages and valid empty mappings, instead of appending another copy of every page. The Memory path
also transfers the extracted sequence out of its result, removing the temporary copy formerly
introduced by `images.value`. Borrowed public frame inputs are copied once into a private sequence
before this consuming boundary; callers retain their original arrays and sequences.

Page-count and host-index bounds remain checked before extraction/allocation. Native descriptors
still point only into frame-owned resident regions. Host remapping constructs a new checked frame;
code caches retain neither input images nor invocation memory. Initial immutable memory capture,
resident byte copies and immutable root-vector replacement are separate remaining costs.

## Verification and measurement

The existing `pvm_memory_chunks` suite transfers image observations, mutates transferred bytes,
and checks the original immutable pages plus a prior copied observation. Its1000-cycle ARC check
covers retirement. Existing stream regions/hosts, complete memory/permission/fault controls and
native/refused execution cover consuming construction, host replacement and snapshot lifetimes.

Baseline is corrected checkpoint head `7060c57ce205c8d3cbacebc3597f463759a47bf2`. Inspect generated ownership
lowering and compare matching checked ARC/Clang/ThinLTO builds on ARM, with construction/public
invocation costs included in their own measurements. Local macOS ARM measurements are authorized
for early feedback; final native qualification remains in CI. Results are pending; no speedup is
claimed from removing source-level copies alone.

## Local ARM early feedback

The prior cohort's frozen `pvm_final_memory.nim` driver at `fc8e18db` was reused without changing
its scenarios or validation. Matched macOS ARM checked ARC/Clang/ThinLTO builds compared the
corrected checkpoint parent with owned images at `2fbded1710504096d1fd57ea304c941614641d13`,
using identical canonical source paths, three warmups and ten measured samples in both orders.
All312 matrix rows per process and full CPU/memory/retained-snapshot controls passed. Live entry
bytes remained equal, as expected: the removed temporaries already retired before that observation.

Across all six scenarios and64–4096 mapped pages, entry CPU time fell29–44% and the measured
public-call-plus-retirement lifecycle fell28–41%. The one-page case is too small for a useful
entry-speed claim. These bounded small-guest observations establish an entry-copy benefit locally;
DOOM init/tick raw CPU and our-time/PolkaVM-interpreted ratios remain the application decision,
with matching ARM CI qualification pending. Raw local scripts, samples, compiler/build arguments
and source/driver identities are retained under `build/pvm-owned-images/measure/`.
