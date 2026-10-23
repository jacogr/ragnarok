# PVM machine snapshots and sparse memory

This increment is stacked on program decoding (#53). It targets Gray Paper **0.8.0**,
commit `07f041dabd073f9018b418e9ee72e79dd2185401`, using the already hashed
`text/overview.tex` (`eq:gasregentry`, `eq:pvmmemory`), `text/definitions.tex`
(page/zone constants), and `text/pvm.tex` (Basic Definition and Single-Step State
Transition). No specification or vector pins change.

## Scope and ownership

`src/pvm/machine.nim` captures thirteen 64-bit registers, a validated program/entry
address through `captureMachine`, unsigned 64-bit gas credit, the block-charged flag, and immutable memory.
Terminal host snapshots also retain a canonical gas deficit as described below. This is
an explicit machine-state constructor, not the standard JAM program initializer.
CPU metadata and page images returned to callers are copies. The program owner
comes from the first increment; memory/program handles retained by a machine stay
valid after their original handles and input buffers leave scope.

`captureTerminalMachine` separately captures a trusted terminal state with valid
program/memory owners and any register-width PC. This preserves the single-step
trap increment beyond code without relaxing executable-entry validation. It does
not authenticate an exit reason; callers follow `StepOutcome.exit` when deciding
whether to execute again. See [single-step terminal semantics](pvm-step.md).

Memory is a sorted sparse sequence of immutable page headers. Each header owns
eight immutable 512-byte chunks and inaccessible/read-only/read-write permission;
the public page image remains 4096 bytes. A missing page has
zero underlying bytes and inaccessible permissions. Inaccessible stored pages
retain their bytes, so changing their permissions need not erase their contents.
`captureMemory` requires sorted unique page ordinals below 2^20 and applies a
caller-supplied materialized-page limit before allocating. Empty captured memory
is valid; a default owner is not.

`withPage` is an environment/setup operation: it copies a supplied complete page,
can change permissions or contents, preserves other pages, and enforces the
original owner's page ceiling for insertions. Replacement at the ceiling is
allowed. This is not a guest store or a host-function implementation.

Published owners form acyclic ARC graphs. Updates copy the page-reference vector and touched headers/chunks, sharing all
other immutable page storage. No backing
reference or borrowed pointer is public. Failure returns only a typed reason;
a guest page-fault address is part of that reason, never partial operation progress.

## Scalar access contract

Loads and stores support widths 1, 2, 4 and 8. Other widths return a local
`InvalidWidth`, not an invented PVM exit. Values are little-endian; loads return
unsigned register values and stores use the requested low bytes. Instruction-
specific sign extension remains the executor's responsibility.

Effective starting addresses use their low32 bits. PolkaVM exclusive-end overflow
is checked before inspecting byte permissions, including a one-byte access atMAX32.
An absent final page faults at0xfffff000; a present ReadOnly/ReadWrite final page
panics. Retained inaccessible images represent absent runtime pages. Nonoverflow
byte checks never rely on an overflowing host sum. The low 64 KiB is always protected, including when supplied
page images mark it accessible, following the explicit prose requirement.
Read-write implies readable. Missing/inaccessible pages fault on either access;
read-only pages fault on writes. A fault reports the aligned physical byte address
of the first inaccessible page in the original increasing access sequence.

All touched page permissions are checked before reading a value or allocating changed pages.
Failed cross-page stores therefore cannot alter their first page. Successful stores
publish a new owner; old aliases remain unchanged. Machine stores replace only
memory and preserve every register, PC, gas and charged flag. `withRegister` and
`withMemory` are explicit state-building operations, not instruction stepping.

Permission lookup is logarithmic in stored pages; a scalar resolves at most two
page slots and reuses those validated slots for its at most eight payload bytes. Snapshot updates currently copy O(stored pages) references. This correctness
baseline has no performance or gas-proportional execution claim. Allocation is
bounded by the page limit; allocation failure itself is not mapped to a VM exit.

## Scoped memory exception and resolved wrapping-access gate

The Gray Paper remains primary. The maintainer approved a scoped memory exception
on2026-10-21: the former wrapping-access gate follows pinned PolkaVM exclusive-end
overflow and final-page-presence behavior at the scalar layer. The
[discrepancy register](graypaper-discrepancies.md) distinguishes the paper
prose/equation ambiguity from the mapped-last-byte deviation. Raw stepping preserves the resulting precise Fault/Panic and paid
gas; JAM invocation normalization remains unchanged. See the
[adoption and completion contract](pvm-polkavm-memory-order.md) for exact pinned
tests, interpreter source evidence, last-byte and read-only edge cases.
The historical AmbiguousAccessOrder reason is retained but no longer emitted.

## PolkaVM cross-checks and fuzz material

PolkaVM is pinned as an implementation cross-check and test-only dependency in `vendor/polkavm` at
`69e5b87c9888bc4f94cabdadc9661cf68a1bfbfa`; `spec/polkavm-pins.json`
records source hashes. Production builds do not build or link the Rust engine.
The original scalar witnesses below were adapted from source. The later optional
[executed memory reference](pvm-memory-boundary-reference.md) runs the public pinned
interpreter to freeze boundary fixtures; ordinary Nim tests replay those bytes.
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
execution-vector gap described in `pvm-program.md` remains. The separate
[single-step executor](pvm-step.md) now integrates memory instructions, gas charging
and fault repair/retry with the approved PolkaVM memory exception ordering.
[Host byte-range access](pvm-host-memory.md) separately provides bounded natural-interval
reads and atomic writes; it preserves scalar instruction semantics. Standard initialization
and host dispatch have separate contracts; concrete host functions and complete JAM invocation remain open.

Terminal host balances now carry canonical gas credit/deficit; see
[host gas accounting](pvm-host-gas.md). Negative snapshots cannot resume execution.


## Scalar page spans, 2026-10-23

The private scalar preflight retains resolved sparse page slots, first-page offset and
bounded byte counts. Loads and stores reuse these slots rather than searching the
page vector for every byte. It preserves owner/width validation, low-32 address
selection, exclusive-end overflow, protected-prefix panic, cross-page store presence
priority and failure atomicity. No unchecked pointer or mutable backing storage is
exposed; successful stores still clone the vector and touched storage before publication.

The native machine suite adds 64 neighboring page pairs separated by holes, checking
unaligned eight-byte loads/stores, every output byte, exact hole faults and retained
aliases across the full sparse vector. The existing independent 4050-case scalar
reference, pinned boundary reference and memory-instruction suite pass; machine and
memory-step owners return to their ARC baselines after 1000 cycles. A compiler guard
keeps the resolved-span helper private. Measurement and remaining copying costs are
recorded in [the interpreter comparison](pvm-benchmark-comparison.md).


## Persistent page chunks, 2026-10-23

A private page header retains eight fully initialized 512-byte chunk owners. Scalar
stores clone at most two touched chunks, including when an eight-byte scalar crosses
a chunk/page boundary. Host writes clone every intersected chunk only after complete
range/permission/copy-budget preflight. All mutation targets private successors;
predecessors and untouched chunks remain immutable. Permission-only successors share
payload owners while preserving predecessor permissions. Zero/remap/free operations
retain their existing byte and page-budget contracts.

The public `PageImage`, 4096-byte guest page, page-count limit and byte-copy policy
are unchanged. `captureMemory` copies all input bytes into private chunks and
`pageImage` materializes a complete independent array; no chunk, reference or mutable
view is exported. Chunk geometry is an implementation detail, not a protocol page
size or a new caller resource policy. Owners remain an acyclic ARC graph.

The `pvm_memory_chunks` native suite retains original/read-only/remapped and three
write generations across nine interior/page boundaries. Independent full-page byte
expectations check overlapping scalar/host writes, input mutation, copy-budget
refusal and unchanged predecessor permissions. A thousand repeated groups release
all owners. Machine, host-memory, scalar/boundary references, memory instruction,
heap mapping, initialization and execution/host suites pass with their ARC evidence.
Compiler probes keep chunk cloning and byte mutation private. The
[benchmark record](pvm-benchmark-comparison.md) reports broad execution improvements,
preparation boundaries and remaining interpreted performance gaps.


## Scalar write epochs, 2026-10-23

`newScalarMemoryWriter` creates an explicitly mutable reference identity from a valid
immutable memory owner. Copied writer handles share progress. Checked scalar `load`
and `store` preserve the existing width/address/permission/fault precedence rules;
a failed store preserves all previous successful writes. Page mappings, permissions
and page budgets remain fixed throughout an epoch. Missing/nil owners return
`InvalidOwner`, and failed/default results expose only their reason.

The first successful write allocates a private page vector and one dirty byte per
admitted page. Each touched header and 512-byte chunk clones only once in that epoch.
`snapshotMemory` transfers the private vector into an immutable memory owner, retires
the dirty map and resets all writer aliases to that immutable base. Later writes
start a fresh copy-on-write epoch. An unchanged epoch returns its existing owner.
No page/chunk/vector reference escapes, and the ownership graph remains acyclic.
The builder is mutable caller state and requires exclusive access during calls.

The scalar-writer suite checks all scalar widths across chunk/page boundaries,
retained source and multiple published generations, shared writer identity,
refused cross-page writes and invalid owners. A thousand complete ownership cycles
return to baseline. Compiler probes keep mutation helpers and page storage private.
