# Fixed-width checked callbacks in the standalone ARM64 whole image

This private experiment follows the rejected revocable native chunk-window variant. Its retained
cohort and independent discard verdict remain unchanged. Pinky sampling assigned about70% of all
samples to checked helpers and17% to the bridge (including setup/correctness; no exact cost claim).

## Hypothesis and boundary

Each memory instruction already has a fixed decoded width, but the original compiler passes that
width to a generic checked callback. Select one of eight helpers during compilation so the existing
production `load[Width]` and `store[Width]` APIs can specialize their checked implementation. Do not
change memory storage, page ownership, COW, checks, faults, gas, source pins or production emitters.
No native data pointer, lease, backing projection or private writer field exists in this variant.

An invocation-local eight-entry immutable function table lives after the original160-byte context.
Generated code loads the exact callback for its decoded width; the original argument, save/restore,
status/PC and failure sequence remain. The emitted memory instruction count is unchanged. Context
size224, table offset160 and all eight typed table entries are cold checked against C before any
image publication. The writer and callbacks remain borrowed only through synchronous execution;
all function pointers and the writer pointer clear before returning the result.

## Qualification and one measurement

Correctness clocks are disabled. Original23 control images plus88 all-width public scalar crosschecks and15 signed/alias/epoch images
exercise ordinary/chunk/page crossings, readonly and missing pages, low32 narrowing, protected prefix,
exclusive-end refusal and last-valid spans. Full initialized Pinky/frame and sieve1000/10m execute
twice per owner in both arms, comparing full state/source/perms. Deliberate assertion and corrupted
frame controls must fail. Independent exact-source and actual correctness review precedes timing.

The source-bound gate and evidence protocol match the previously reviewed native-memory harness:
complete owned/dependency path sets and hashes, compiler/build configuration, original oracle bytes,
review receipt and correctness archive, generated projection equality except explicit clock changes,
per-process and final seals. All source/image/log bytes remain under unique ignored build directories.

Use offline already-provisioned tools only:

```sh
make check-pvm-whole-width
make check-pvm-whole-width-compare \
  PVM_WHOLE_WIDTH_CORRECTNESS=/absolute/correctness-evidence \
  PVM_WHOLE_WIDTH_REVIEW=/absolute/independent-review.json
```

One balanced serial Pinky+sieve matrix: baseline/variant and reversed order,13 fresh processes per
cell, first3 discarded,10 retained,2 calls per owner:104 processes208 calls. Keep only consistent gains
above noise in both guests/orders with all semantic gates; otherwise discard. No sweep, compiler flag
change, production adoption or paused-peer implementation. Both arms gasOFF, restore/publication
outside invocation, original reference oracles/pin69e5 and production8bcb held. Compiler identities
are hashes/versions; SDK/sysroot/registry are not a completely retained build environment.
