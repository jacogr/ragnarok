# Complete scalar memory-access comparisons

## Normative scope

The primary source is Gray Paper 0.8.0
`07f041dabd073f9018b418e9ee72e79dd2185401`, `text/pvm.tex`: memory exceptional
execution and opcode mutation equations. Pinned PolkaVM
`69e5b87c9888bc4f94cabdadc9661cf68a1bfbfa` is a public-API cross-check. No pins,
compiler sources, upstream code or production dependency boundaries change.

The independent Python reference derives literal encodings, effective addresses,
signed loads, low-byte stores and the first nonwritable/unreadable index without
using a production decoder or evaluator. The frozen corpus is GP-derived, including
the GP-PVM-008 fault address that differs from PolkaVM. All reads/writes are above
the protected zone, below overflow and confined to two neighboring 4096-byte pages.

## Consolidated coverage

| Dimension | Cases |
| --- | --- |
| Opcode forms | All 30: immediate stores 30–33, direct scalar 52–62, indirect immediate stores 70–73, indirect register scalar 120–130 |
| Widths | 1, 2, 4 and 8 bytes, with signed/unsigned load pairs where defined |
| Starts | `0x10000`, `0x10ff8`, `0x10ffc`, `0x10fff`, `0x11000` |
| Permissions | All nine absent/read-write/read-only page pairs |
| Variants | Distinct A/B, aliased A/B, saturated raw register nibbles; offsets 0, +1, −1; nonzero upper base bits |
| Byte/value witnesses | Unequal page-spanning bytes, positive/negative signed loads, zero and negative immediate stores, full-width register stores |
| Posterior checks | All 13 registers, exact exit/fault PC mapping, all mapped bytes, permission preservation and native source aliases |

The Cartesian matrix contains 4050 records. Each record has a 234-byte fixed header
and a bounded raw blob: blob length, paper exit/fault, effective address, width,
permissions, pattern seed, successful write length/bytes, 13 input registers and
13 expected registers. `PVMMAC01` plus a u32 count precedes the records.
The fixture descriptor pins SHA-256
`70f725c62dc88c1e211009fa32eb936ec057f9b6d72142775cfb3814055865c4`.

A real trailing trap lets PolkaVM run the memory instruction to completion. For
success, native single-step stops at that trap's PC; the interpreter then traps at
the same PC. Faults retain the memory instruction's PC zero. This documented
boundary mapping avoids conflating a successful memory operation with the trailing
trap. Gas/cycle parity is outside this unmetered matrix.

## New discrepancy and explicit compatibility

The first cross-check failed at row 234: u16 immediate store at `0x10fff`, lower
page read-only, higher page absent. The GP first denied index is on `0x10000`;
PolkaVM checks missing mappings before writability and reports `0x11000`.
See [GP-PVM-008](graypaper-discrepancies.md#gp-pvm-008-missing-mappings-precede-read-only-faults-in-cross-page-stores)
and the prepared local issue draft. No issue was posted.

The frozen bytes retain the paper expectation. Both replay consumers explicitly
adapt exactly 48 multi-byte-store rows to the documented reference fault. The
production scalar owner applies the same narrow missing-mapping priority before
its existing writability checks. Protected-low and exclusive-end rules still run
first. The dense scalar and instruction matrices retain their independent byte
references and add this named priority exception. Failed stores remain atomic.

The public checker additionally verifies `Segfault.is_write_protected`; the native
Fault API carries the page address. All 8192 native owned bytes are checked,
including inaccessible retained images, while the public API permits observation
only of mapped pages. No full upstream test/fuzz or compiled-backend parity is claimed.

## Reproduction and completion

```sh
make unit SUITE=pvm_memory_access_reference
make unit SUITE=pvm_machine
make unit SUITE=pvm_memory_step
make check-pvm-reference
```

The new executable owns its runner declaration, so the existing Linux comparison
job discovers it without a job edit or a separate PR per table entry. Independent
Python tests verify frozen bytes, full opcode coverage, exact signed values and
48 unchanged paper/reference differences. Tampered expected registers and malformed
record lengths must fail both consumers. Complete invocation combinations and
metered repair of this priority case remain subsequent work.

## Observed local evidence

The independent/public/native matrix passes all 4050 rows, with exactly 48 named
GP-PVM-008 adaptations. Corrupted expected-register and oversized-record-length
inputs are rejected by both native and public replay consumers. The dense memory
owner and all-form instruction suites pass, each with stable 1000-cycle ARC
observations (124752 and 17664 occupied bytes respectively). The complete integrated
runner passes all ten declared reference/native pairs. Ten focused Python tests,
inventory and pinned formatting checks pass. Evidence is local macOS checked release
ARC/Clang LTO and pinned Rust release; remote Linux CI has not been requested.
