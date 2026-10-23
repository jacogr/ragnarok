# Pinned real-sieve guest

This linked JamV1 fixture uses the unchanged `bench-prime-sieve` sources from pinned
PolkaVM69e5b87c9888bc4f94cabdadc9661cf68a1bfbfa. Upstream credits
[PrimeRust solution_1](https://github.com/PlummersSoftwareLLC/Primes/tree/708075dd82f5f1aa92c56c5cfd15338f524f03c0/PrimeRust/solution_1).
Both upstream license texts are retained here. The project-owned checked entry is
appended to upstream main.rs; it adds prime counting and validation, so these runs
must not be compared directly with published stock sieve scores.

`provenance.json` pins every upstream source/lock/target, the exact linked artifact,
checked entry, guest lock and build profile. Ordinary benchmark reproduction reads
this immutable artifact; it does not install or invoke the older guest compiler.
The repository's current pinned host Rust and Nimony build the two interpreter hosts.

For an explicit guest rebuild, use the recorded nightly with rust-src and the pinned
legacy target. In an ignored build directory copy upstream main.rs, unrolled.rs,
unrolled_extreme.rs and bench-common.rs without edits; append checked_entry.rs.inc.
Use the original Cargo manifest with helper-macros, simplealloc and polkavm-derive
paths redirected to the pristine pinned vendor tree, the retained guest-Cargo.lock,
and the exact profile/command in provenance.json. Link the resulting ELF through
the pinned public program_from_elf API with default Config and JamV1. Any differing
artifact requires an explicit reviewed fixture-pin update; benchmark setup never
silently replaces this file. Original build evidence is referenced in PR1309.
