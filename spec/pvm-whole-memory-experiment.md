# Private whole-image checked-memory experiment

This is one local ARM64 diagnostic, with gas deliberately disabled. It changes no production
source, public API, policy, quota, default, upstream pin or #1811 adoption hold. The initial
whole-image sieve and Pinky cohorts remain immutable. The separate upstream pin qualification
must not relabel these old-pin observations as upgraded evidence.

The source baseline is `8bcb461b866f0edb970b6542ad9823f9aaa3050a`; reference fixtures and original
oracles use PolkaVM `69e5b87c9888bc4f94cabdadc9661cf68a1bfbfa`. The pinned Nimony/ARC/Clang checked
release profile remains unchanged. Actual qualification covers Darwin ARM64; Linux is untested.

## Evidence and scope

The initial Pinky cohort measured one original `benchmark_run` and ABGR framebuffer conversion
from the same nine-frame initialized NES state on every call. It is not a continuing sequence of
NES frames. The independent full-state and 245760-byte rendered-output oracle is reference-derived,
not an independent NES golden. Both initial three-engine cohorts retain their gas and ownership
scope differences; their ratios are not production-equivalent throughput claims.

A separately labelled macOS sampling diagnostic of 160 full-state/frame-checked Pinky calls used
cold generated-PC annotations and retained native code bytes. Exclusive stack leaves attributed
about 70% of samples to checked-memory helpers and their descendants, about 17% to native bridge
setup/save/status/restore work, and about 8% to generated guest instructions. Loader/correctness
and unattributed samples remain explicit. These statistical shares are not exact scoped CPU
milliseconds or an isolation of microarchitectural call/spill cost. The original sole comparison
cohorts are not rerun or overwritten by this diagnostic.

## One structural variant

The private projection uses readable licensed source fragments and single exact replacement anchors;
a generated-text regression binds the emitter, backing and C ABI to the executed prototype, including
Nim indentation. The private projection textually consumes the production `machine.nim` implementation. It adds
one saturating writer revocation generation and invalidates it before **both** public writer
store overloads and **every** `snapshotMemory`, including failed stores and unchanged publication
through a copied alias. Existing permission/span checks, COW/dirty preparation and payload code
remain unchanged. Generation saturation never wraps and permanently disables new raw leases.
No private writer/page layout is guessed or cast to an external struct; no flat or mirrored guest
memory is created.

Only the private image module can create a chunk descriptor. A readable descriptor comes from an
actual retained readable page. A writable descriptor additionally requires the exact active
page/slot and its real current-epoch dirty bit proving the 512-byte chunk already private. Every
slow helper retires pointer authority and reacquires it only after the original successful scalar
operation. Integer tags can remain as reacquisition hints; they are not permissions.

Generated native loads/stores check the complete narrowed 32-bit span, protected prefix, original
exclusive-end boundary, within-chunk extent, exact tag, nonnil pointers and the live shared alias
generation **before** dereferencing actual production chunk storage. Cross-chunk/page accesses,
permission failures, new COW work and every miss retain the original checked helper. Native hits
skip the call/spill bridge; actual direct hits and remaining helper calls are separately counted.
The private writer is retained for the synchronous invocation, no guest host callback can reenter,
and every writer/chunk/generation/probe pointer is cleared before the returned result. Ordinary
concurrent access to a mutable scalar writer is outside its original ownership contract.

Correctness-only probes deliberately operate through a copied writer alias while a descriptor is
armed in the **same** invocation: read then COW, writable and unchanged seals, overlapping/failed
stores, public static-width stores, and the final generation increment. They verify actual native
misses, immutable saved snapshots and refusal to reseed after saturation. Additional controls
cover all widths, signed/address-register aliases, low32 narrowing, chunk/page/final-byte/protected
boundaries, readonly/missing pages, atomic failed stores and error PCs. Probe code is absent from
timing callbacks. Full Pinky and small/long sieve checks compare every register, mapped byte,
permission, source, independent sieve prime result and terminal state; guest clocks are disabled.

## Commands and gate

`make check-pvm-whole-memory` requires existing pinned tools and runs only the inert inventory
plus this private correctness pipeline. It never provisions tools or fetches dependencies. A
unique directory retains pre-build consumed sources, projected sources, actual images, raw logs,
compiler/input/oracle identities and the final seal even on failure.

The exact committed source and source-bound actual correctness report require independent review
before timing. The gate rechecks complete owned-source/configuration and non-Git dependency path sets
and hashes, compiler identity/version and build configuration against that reviewed manifest before
derivation/build. Generated backing/emitter/header bytes must be identical; only the explicit guest
clock projection may change in four drivers. The consumed correctness archive is hash-checked before
and after copying. Per-process/final seals reject new files or source changes. Its receipt binds `revision`, `source_correctness_gate: passed`, and
`correctness_results_sha256`. After that gate:

```sh
make check-pvm-whole-memory-compare \
  PVM_WHOLE_MEMORY_CORRECTNESS=/absolute/path/to/correctness-evidence \
  PVM_WHOLE_MEMORY_REVIEW=/absolute/path/to/independent-review.json
```

Exactly one balanced serial matrix compares unchanged whole-image and the single native-memory
variant, both gas-off with the same ownership scope: Pinky and long sieve, both arm orders,
13 fresh processes per arm/order/guest, first 3 discarded and 10 retained, 2 calls per owner.
That is 104 fresh processes and 208 timed calls. Program/code owners are reused; guest state is
reset identically. Compilation/preparation, first/reused-owner execution, restore/publication
and image retirement are separate. Final writer/Program/Memory destruction is not individually
isolated. No equivalent production lifetime total or upgraded upstream claim is constructed.

Keep this private direction only for consistent gains in both guests and both orders with all
semantic gates. Mixed/noisy/regressing transfer means discard this variant. Either verdict ends
this bounded experiment; it does not authorize another cache strategy, instruction polishing,
production adoption, quota/default changes or a public performance PR.
