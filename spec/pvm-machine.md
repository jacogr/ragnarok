# PVM machine snapshots and sparse memory

This increment is stacked on program decoding (#53). It targets Gray Paper **0.8.0**,
commit `07f041dabd073f9018b418e9ee72e79dd2185401`, using the already hashed
`text/overview.tex` (`eq:gasregentry`, `eq:pvmmemory`), `text/definitions.tex`
(page/zone constants), and `text/pvm.tex` (Basic Definition and Single-Step State
Transition). No specification or vector pins change.

## Scope and ownership

`src/pvm/machine.nim` captures thirteen 64-bit registers, a validated program/entry
address through `captureMachine`, unsigned 64-bit gas, the block-charged flag, and immutable memory. This is
an explicit machine-state constructor, not the standard JAM program initializer.
CPU metadata and page images returned to callers are copies. The program owner
comes from the first increment; memory/program handles retained by a machine stay
valid after their original handles and input buffers leave scope.

`captureTerminalMachine` separately captures a trusted terminal state with valid
program/memory owners and any register-width PC. This preserves the single-step
trap increment beyond code without relaxing executable-entry validation. It does
not authenticate an exit reason; callers follow `StepOutcome.exit` when deciding
whether to execute again. See [single-step terminal semantics](pvm-step.md).

Memory is a sorted sparse sequence of immutable page references. Each page owns
4096 bytes and inaccessible/read-only/read-write permission. A missing page has
zero underlying bytes and inaccessible permissions. Inaccessible stored pages
retain their bytes, so changing their permissions need not erase their contents.
`captureMemory` requires sorted unique page ordinals below 2^20 and applies a
caller-supplied materialized-page limit before allocating. Empty captured memory
is valid; a default owner is not.

`withPage` is an environment/setup operation: it copies a supplied complete page,
can change permissions or contents, preserves other pages, and enforces the
original owner's page ceiling for insertions. Replacement at the ceiling is
allowed. This is not a guest store or a host-function implementation.

Published owners form acyclic ARC graphs. Updates copy the page-reference vector
and at most the touched pages, sharing all other immutable pages. No backing
reference or borrowed pointer is public. Failure returns only a typed reason;
a guest page-fault address is part of that reason, never partial operation progress.

## Scalar access contract

Loads and stores support widths 1, 2, 4 and 8. Other widths return a local
`InvalidWidth`, not an invented PVM exit. Values are little-endian; loads return
unsigned register values and stores use the requested low bytes. Instruction-
specific sign extension remains the executor's responsibility.

Effective byte addresses wrap modulo 2^32. Masking before adding each bounded
byte offset also handles an input address at UINT64_MAX without relying on an
overflowing host sum. The low 64 KiB is always protected, including when supplied
page images mark it accessible, following the explicit prose requirement.
Read-write implies readable. Missing/inaccessible pages fault on either access;
read-only pages fault on writes. A fault reports the aligned physical byte address
of the first inaccessible page in the original increasing access sequence.

Every touched byte is checked before reading a value or allocating changed pages.
Failed cross-page stores therefore cannot alter their first page. Successful stores
publish a new owner; old aliases remain unchanged. Machine stores replace only
memory and preserve every register, PC, gas and charged flag. `withRegister` and
`withMemory` are explicit state-building operations, not instruction stepping.

Permission lookup is logarithmic in stored pages; an access checks at most eight
bytes. Snapshot updates currently copy O(stored pages) references. This correctness
baseline has no performance or gas-proportional execution claim. Allocation is
bounded by the page limit; allocation failure itself is not mapped to a VM exit.

## Explicit unresolved specification gate

For a two-byte access starting at `0xffffffff` with the high page inaccessible,
the original requested indices are `{2^32-1, 2^32}`. The formal exception equation
selects `min(x) = 2^32-1`, giving a fault at `0xfffff000`. The prose instead says
that requiring a byte below 2^16 always panics, and the second physical byte is zero.
The equation also does not encode the prose's unconditional low-address protection
when a caller supplies accessible low pages. Ordinary low-page access implements
the explicit protection requirement; it is not made accessible through page images.

For the conflicting high-page-fault/low-page-wrap case, this implementation returns
`AmbiguousAccessOrder`, an explicit local specification gate. It is neither panic,
fault nor a resumable PVM execution result. Focused pending-gate assertions retain
both load and store witnesses (including UINT64_MAX). A future executor must resolve
this pinned-text discrepancy before claiming full memory semantics/conformance; it
must not silently convert the gate to a consensus exit. If the high page is accessible,
wrapping into protected memory unambiguously panics. Non-wrapping faults and panics
are implemented and tested normally.

## PolkaVM cross-checks and fuzz material

PolkaVM is pinned as a test-only upstream in `vendor/polkavm` at
`69e5b87c9888bc4f94cabdadc9661cf68a1bfbfa`; `spec/polkavm-pins.json`
records source hashes. No Rust engine or upstream scripts are built or run.
The native suite adapts two witnesses from `crates/polkavm/src/tests.rs`:

- `dynamic_paging_write_at_page_boundary_with_first_page`: store `0x12345678`
  at `0x10ffe`, fault at `0x11000` without a partial write, supply the missing
  page and retry; verify the literal bytes on both sides and the old snapshot.
- `dynamic_paging_read_at_page_boundary`: fault at `0x10000` with no pages,
  then read `0x00bbaa00` from bytes `aa bb` straddling `0x11000`, with both
  read-write and read-only permissions.

These are scalar memory cross-checks, not instruction execution vectors. We fix
pages to GP's 4096 bytes, manually retry the memory API, and do not claim PolkaVM's
host mapping, instruction resumption, signed extension or gas behavior. The values
and failure atomicity agree with the GP definitions cited above. Upstream's
`memory_access_with_upper_address_bits_set` expects an engine trap with unmapped
memory; it is not imported as a JAM panic/fault oracle.

The pinned tree also has RISC-V assembly tests and fuzz targets for program blobs,
instruction decoding, page sets and VM execution. `fuzz_polkavm.rs` constructs
`Latest64` programs; with `CORRECTNESS_FUZZER` it compares interpreter/compiler
interrupts, PCs and all registers. This is a useful future differential harness,
but requires an explicit GP opcode/encoding/gas compatibility adapter. It does not
currently compare memory contents. `fuzz_page_set.rs` compares operation sequences
against a naive bitset, a useful model for later stateful memory fuzzing.

`fuzz/.gitignore` excludes `corpus`, `artifacts` and `coverage`; no saved crash corpus
was located in this pinned tree. `ci/jobs/fuzz.sh` runs bounded fuzz campaigns.
These harnesses and their CI execution are not claimed as replayed fuzz results.
When importing minimized crash inputs, pin their provenance and preserve the
original witness separately from any GP-compatible adaptation.

## Verification and next increment

The native `pvm_machine` suite covers all 256 public width/register-index values,
all nine permission pairs across protection/page/mapping boundaries, a dense byte
reference for loads and atomic stores, 32/64-bit address extremes, sorted/duplicate
page validation, resource ceilings, retained inaccessible contents, copy isolation,
CPU-state preservation and 1000 complete ARC release cycles. Eight compiler guards
protect owners, result state and nominal domains. Five isolated runtime misuse
probes enforce value-versus-fault selection through the existing failure harness.

No standalone official PVM execution corpus is claimed by these tests. The pinned
execution-vector gap described in `pvm-program.md` remains. Next: instruction
execution in bounded opcode groups, with gas charging and exact exceptional state
semantics grounded in the pinned specification. This increment does not implement
gas charging, halt/host-call outcomes, page-fault resumption, standard initialization,
host functions or any complete JAM invocation.
