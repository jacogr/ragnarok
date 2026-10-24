# Frozen checked interpreter guests

The indirect-call and memory-fill algorithms come from pristine pinned PolkaVM
69e5b87c9888bc4f94cabdadc9661cf68a1bfbfa, `bench-minimal` and `bench-memset`.
Both upstream licenses are retained. Project-owned checked entries validate sizes
1,000 and 100,000 and supplement complete interpreter state comparison. These
adapted checked runs are not published stock benchmark scores.

Minimal resets the original state and invokes the unchanged function-pointer loop
`limit` times, returning `2*limit + limit%2`. Memory fill retains the exact original
source prefix through `benchmark_run`, excluding unrelated custom accelerated,
naive and compiler-builtins exports; its unused compiler-builtins dependency is
omitted. The checked entry resizes the existing vector to `limit`, calls the original
fill once, verifies byte zero and every filled byte, then returns `limit-1`. The
original 4 MiB static allocator remains mapped. Allocation and validation execute
inside the guest and are included in execution timing in both interpreters.

Normal `make bench-pvm-guests` reads the frozen artifacts. It neither installs nor
invokes the historical guest compiler. Every artifact, entry, lock, manifest,
provenance and license has an explicit descriptor digest. Provenance records the
unchanged upstream files, retained memory-fill prefix and exact build profiles.

For an explicit rebuild, create `guest-programs/bench-{minimal,memset}/src/main.rs`
in an ignored directory. Copy unchanged upstream minimal main and the recorded
memset prefix, then append each checked entry verbatim. Copy upstream bench-common.rs
beside those package directories. Use workspace.Cargo.toml as the workspace manifest,
the retained package manifests as each package's Cargo.toml, replacing
`@POLKAVM_ROOT@` with the pristine pinned vendor path, and guest-Cargo.lock. With the
recorded nightly/rust-src and legacy target, execute the command and path-remapping
flags in provenance. Link each resulting ELF with pinned public `program_from_elf`,
default Config and JamV1. No source, toolchain or dependency upgrade is implied;
changed artifact bytes require a reviewed fixture update. Original build evidence
is retained under build/pvm10/guest-pack-probe.
