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

Baseline is checkpoint head `0933eec54ca04a5fa46fe8084630d98122d3271a`. Inspect generated ownership
lowering and compare matching checked ARC/Clang/ThinLTO builds on ARM, with construction/public
invocation costs included in their own measurements. Local macOS ARM measurements are authorized
for early feedback; final native qualification remains in CI. Results are pending; no speedup is
claimed from removing source-level copies alone.
