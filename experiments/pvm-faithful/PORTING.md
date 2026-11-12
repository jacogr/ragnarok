<!-- Copyright (c) 2026 Ragnarök contributors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->
# Faithful-style interpreter control

## Purpose and authority

The maintainer authorized this standalone diagnostic on 2026-11-12: compare a fresh Nimony
translation of PolkaVM's interpreter architecture with unchanged interpreted PolkaVM across
Ragnarök's current 22 workloads. This does not replace production code, change Gray Paper authority,
or relax the immutable production API contract. Its mutable instance is an explicit experimental
exception. The historical `ac4ba21c` comparison is excluded as an architectural baseline.

- PolkaVM: `471a5b68f9dfa41e49b5d2fe80c394c1a8d68a3d`.
- Frozen benchmark/master-CI baseline: `c8e384caddce9826e58be45b0084ba7e2d5adf5b`.
- Nimony: `fd9742bf1939a1b754144506e89a8acb0e7b747a`, ARC, Clang ThinLTO, bounds/assertions enabled.
- Rust: `1.99.0`; ordinary interpreted dispatch, no musttail or compiled reference backend.

No production execution, decoding, gas planning, memory publication, JIT or prepared-program
implementation supplies the fresh engine. Existing tools supply frozen fixtures, provenance,
unchanged Rust drivers and strict reference-output parsing only.

## Architecture and source mapping

| Owner | Pinned upstream source | Preserved mechanism |
| --- | --- | --- |
| `buffer.nim`, `shared_bytes.nim` | Vec / ArcBytes ownership | Exclusive mutable buffers, retained immutable slices, explicit moves |
| `page_map.nim` | Rust 1.99 `alloc/collections/btree/{node,search,entry,map,navigate}.rs` | B=6, 11-key nodes, linear search, insertion-position splits, parent edges, single descent, in-order consuming teardown |
| `dynamic_memory.nim` | `interpreter.rs` DynamicMemory | Boxed pages, ordered page map, permissions, preflight, crossings and partial host reads |
| `standard_memory.nim`, `memory_layout.nim` | StandardMemory and ABI memory map | Lazy RW/stack/aux vectors, initial-data sharing, retained capacities and allocation limits |
| `program.nim`, `decode.nim`, `opcodes.nim` | `common/program.rs` | JamV1 blob admission, raw operands, bounded/unbounded iteration and legacy jump rules |
| `operations.nim`, `wide_arithmetic.h` | `common/operation.rs` | Wrapping arithmetic and signed/unsigned high-half multiplication |
| `simulator.nim`, `simulator_tables.nim` | `common/simulator.rs` | Full L2Hit/B64 scheduling, 32-entry ROB, vector masks, dependency/resource release, register renaming, source opcode visitor |
| `compiled_offsets.nim`, `plain_vector.nim` | CompiledOffsets / Vec | Epoch-tagged offsets and separate function-pointer / 16-byte argument arrays |
| `engine.nim`, generated `engine_*.nim` | InterpretedInstance / Compiler / raw handlers | Lazy block compilation, ordinary function-pointer dispatch, cached branch arms, whole-block gas, mutable suspend/resume |
| `benchmark_{synthetic,guest,doom}.nim` | Current Rust benchmark embeddings | Matching restoration, host dispatch, normal outputs and independent complete-state validation |

The compiler switches on opcodes while lowering. Execution follows handler function pointers;
it does not switch on opcodes, fuse blocks or introduce guest-specific fast paths. Host interrupts
expose the same stopped mutable instance. Resuming does not publish an immutable machine snapshot.

## Supported profile and disclosed differences

This is a complete execution control for the benchmark profile, not the entire upstream library.
JamV1/B64, synchronous Full(L2Hit) gas, standard memory, dynamic memory and every benchmark host
operation are implemented. Other ISAs are rejected. Debug tracing, instruction metering, the native
compiler, free-pages API, aux-write-protection setters and cache-limit configuration are not exposed.

Language/runtime differences remain observable and must accompany timing results:

- Nimony ARC replaces Rust atomic Arc. Exclusive byte vectors use libc allocation; ordinary
  Rust/Nimony object layout, borrow lowering, inlining and bounds-check code generation may differ.
- `ProgramBlob.parts.encodedCode` retains one additional immutable section handle for independent
  fixture verification. Upstream drops that section handle after splitting it. This changes cold
  ownership bookkeeping; it introduces no per-host-call snapshots or byte copies.
- Engine/configuration wrappers are represented by the selected module profile rather than the
  entire upstream configurable API. Cold results therefore include different configuration-wrapper
  work. Module validation, layout, instance creation and lazy lowering remain inside the cold clock.
- Public host failures retain error categories, not Rust's allocated diagnostic strings/address
  payloads. Successful benchmark calls do not format errors.
- Memory helpers are factored into Nimony routines with source-equivalent checks and allocation
  order. Compiler optimization quality is part of the language comparison, not assumed equivalent.
- The three i128 arithmetic expressions and SIMD movemask are small inline C primitives. The gas
  scheduling logic stays Nimony. ARM uses the same portable lane-array approach as picosimd.
  On x86, the build wrapper applies AVX2 only to the simulator C unit; upstream annotates individual
  scheduling functions. Every compiler invocation is recorded. No toolchain is patched.
- The B-tree field order matches actual Rust 1.99 ARM64 DWARF, not source declaration order:
  parent=0, values=8, keys=272, parent-index=316, length=318; leaf=320, internal=416, page=24 bytes.
  The runner verifies the actual reference DWARF layout on each architecture before timing;
  candidate debug/release tests assert those same sizes and offsets.

These are disclosed translation boundaries, not a promise of instruction-for-instruction parity
or a prediction that results will be near 1.0x.

## Measurement contract

The 22-case inventory comes from the maintained harness: eleven synthetics, nine guests and
DOOM initialization/tick at warmup 1320. JIT explicitly aliases this interpreter; it does not compile
native code. Both role labels must independently pass the same full-state and refusal controls.

The primary window is `full-invocation-v1`: cold code admission, instance creation, restoration,
host work and normal output exposure are included. Reused calls retain lowered code and restore
invocation state inside the clock. Complete memory/register/gas/event comparisons run afterward.
No component duration is subtracted. Sample 0 is cold; samples 1–2 are warmups; samples 3–12 form
the reused median. All thirteen process-CPU and wall samples remain in raw evidence.

Qualified performance requires native Linux Actions, matching runner/host/source identity, clean
source, passed source-bound differential checks, actual simulator SIMD evidence, all full-state
and negative controls, independent reference/reference runs, and both candidate/reference process
orders. Reports use `faithful-control-v1`; fresh records cannot impersonate production JIT policy.
The strict comparator rejects missing cases/samples, foreign scope, aliases, zero clocks and
incomplete success framing. A failed run cannot publish a partial successful table.

Saved master CI timings from run `43197869445` are reused; master is not rerun. ARM CPU part was
`0xd49`; x86 was AMD EPYC 9V74. New paired ratios are valid on their own runner; a different CPU
model does not establish a strict cross-run improvement against those saved master results.

## Reproduction and evidence

Make owns provisioning and recurring commands:

- `make check-pvm-faithful`: pristine reference witnesses, deterministic duplicate generation,
  debug and checked release/ASan slice/engine replay, assertion/corruption refusals.
- `make check-pvm-faithful-workloads`: all 22 complete workloads and refusals, both role labels;
  correctness only, no duration records or ratios.
- `make check-pvm-faithful-asan`: the same full workload checks with AddressSanitizer.
- `make bench-pvm-faithful`: native Linux qualified paired comparison; refuses local timing.
- `make format-pvm-faithful`: pinned formatting of handwritten and generated experiment source.
- Manual `ci.yml` suite `bench-pvm-faithful`: independent native ARM64/x86 jobs. No push or PR
  label triggers this experiment. No PR creation or production change is part of this task.

Raw inputs, logs, assembly and receipts live under ignored `build/pvm-faithful/`. `check.py
--compiler` and `benchmark.py --compiler` may select an already installed compiler; archive
identity/version are verified. Check mode explicitly sets `performance_qualified: false`.

Independent local evidence includes 204,800 raw operand cases, 320 instruction streams,
2,127 blob inputs, 59,049 layouts, 4,217 arithmetic pairs, 1,152 gas-simulator sequences,
4,368 execution modules (2,496 accepted; 9,984 invocations; 23,341 interrupts), 840 complete
host-API cases and 720 standard-memory cases. B-tree tests cover 4,096 keys in three insertion
orders plus traversal, moves and destruction. Deliberately corrupted expectations must fail.

The untouched upstream baseline passed 1,395 library tests (two ignored), 31 common-library
tests and 70 SIMD-enabled common tests locally. This does not claim that upstream's own suite
runs against the translated engine.

All 22 workloads have passed locally, also under AddressSanitizer, in both role labels,
including complete DOOM event bytes
and the upstream video golden. ARM64 generated tick loops contain packed arithmetic and comparison
instructions. Native Linux ARM64 and x86 performance runs have now passed on the same CPU models as the
saved master baseline. [RESULTS.md](RESULTS.md) records the exact tested revision, artifacts,
full comparison and limitations. The results do not support a wholesale interpreter replacement.

Source attribution and license texts are in [LICENSES/NOTICE.md](LICENSES/NOTICE.md).
