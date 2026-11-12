<!-- Copyright (c) 2026 Ragnarök contributors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->
# Third-party source attribution

This experimental translation derives memory, decoding, arithmetic, gas-simulation and interpreter algorithms from PolkaVM
(paritytech/polkavm), commit `471a5b68f9dfa41e49b5d2fe80c394c1a8d68a3d`.
PolkaVM is distributed under MIT OR Apache-2.0; both original license texts are preserved here.
The translation changes the implementation language and is not an upstream PolkaVM release.
`PORTING.md` identifies mapped modules, tests and known translation differences.

`page_map.nim` also follows the Rust 1.99.0 standard library BTreeMap node layout,
linear search, insertion-position splitting, upward insertion and consuming teardown algorithms. Those algorithms
are by the Rust Project Developers, distributed under MIT OR Apache-2.0. Source paths:
`library/alloc/src/collections/btree/{node,search,map,entry,navigate}.rs` in the pinned rust-src component.
This is a restricted page map translation, not a complete Rust BTreeMap implementation.

Project-added harnesses and translations retain the Ragnarök contributor notice. No upstream
source or dependency pin is modified by the experiment.

`simulator_simd.h` reproduces the picosimd 0.9.6 movemask primitive used by the pinned
PolkaVM simulator (MIT OR Apache-2.0). Scheduling and vector operations remain in Nimony.
