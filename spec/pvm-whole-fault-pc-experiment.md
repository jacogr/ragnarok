# Fault-PC publication at the checked-memory failure boundary

The accepted fixed-width callback experiment at4d72 is this standalone ARM64 baseline. Its original
cohort and rejected native-chunk experiment remain preserved. A new separately labelled160-call
Pinky sample retained identical helpers/instructions with cold native-PC mapping. Of5029 exclusive
samples, checked helpers occupy63.27%, bridge PC setup4.51%, arguments8.51%, status4.69%, saves1.93%
and restores1.77%. Sampling includes startup and correctness and does not isolate instruction costs.

## One hypothesis

The static-width helper ignores its former runtime-width argument. Carry the instruction's source PC
in that same load-X2/store-X3 argument instead, and publish context.pc only in the original checked
failure branch. Remove the eager memory setPc operation. Preserve exact width specialization and
original permission/bounds/owner/COW/cross-page/atomic-failure semantics, register save/restore,
status checks, panic normalization, fault page, one-exit behavior and synchronous borrowed ownership.
No data lease, new writer state, production changes, gas changes or additional arguments.

For each static memory site, the former PC immediate moves to the old width argument slot; the old
context load, PC store and width immediate disappear. The exact code reduction is12 bytes per site.
Both drivers report static memory-site counts and assert baseline code size or that reduction;
comparison parsing requires the same count for both arms and every process. Host callbacks gain a
failure-only PC assignment. Successful PCs may remain stale internally but cannot be observed:
there are no guest hostcalls/observers, and every actual final halt/panic/fault publishes the required
PC. Dynamic/control failures keep their original eager metadata publication unchanged.

## Gates and one fixed pair

The new projection derives the accepted width compiler unchanged into width_image.nim as baseline;
only the eight selected callbacks and memory emission sites differ in fast_image.nim. Memory storage,
callback table ABI and all other compiler code remain byte-identical. The previous126 control images
remain, plus16 all-width failures at PC6 after a successful helper, preserving caller-saved destination
registers and earlier successful stores. Prefix panics still normalize to zero. Full initialized Pinky
frame and sieve1000/10m state checks execute with clocks disabled before independent source/actual
review. Exact source/dependency/compiler/configuration/oracle/archive and projection seals are the
previously reviewed protocol. No performance run may precede independent gate receipt.

```sh
make check-pvm-whole-fault-pc
make check-pvm-whole-fault-pc-compare \
  PVM_WHOLE_FAULT_PC_CORRECTNESS=/absolute/correctness-evidence \
  PVM_WHOLE_FAULT_PC_REVIEW=/absolute/independent-review.json
```

One serial balanced104-process208-call Pinky/sieve baseline/variant matrix: both orders,13 fresh
owners per cell, first3 discarded,10 retained,2 calls each. Keep only if all16 CPU/elapsed first/reuse
median baseline/variant ratio cells exceed1.05 and at least8/10 paired retained owners improve in
every cell. Otherwise discard without sweeps/repeats. Same guests, source work, full state/frame,
pins69e5+production8bcb, ARC/Clang/ThinLTO/checks and gasOFF diagnostic scopes. Restore/publication
stay outside invoke, final destruction is not individually isolated; SDK/environment not fully
retained. A private win is no proof of JIT benefit: production has a different existing memory path.
