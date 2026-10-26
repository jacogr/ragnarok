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


## Checked chunk-aware scalar reads, 2026-10-23

Immutable scalar loads retain the existing full-width preflight before reading
either page. Staged loads may reuse page permissions under the invocation-local
window contract below. They now gather each admitted page span with one private
helper, selecting the active writer page once per span. Within one512-byte chunk,
a little-endian host copies exactly the admitted1–8 bytes into an initialized private
uint64. This uses the pinned stdlib's unaligned-safe `copyMem`; source and destination
are disjoint, and no raw chunk pointer or borrowed view escapes the call. Ownership,
reference counts, immutable snapshots and write epochs retain their existing rules.

The helper requires a positive count no greater than8, an offset within4096 bytes,
and `count <=4096-offset`. The chunk-local check `within <=512-count` proves the
complete copy extent before taking its address; a private native word supplies at
least8 destination bytes. The word starts at zero, so partial reads zero-extend.
A two-byte host-order observation chooses the fast copy only for little-endian hosts;
big-endian hosts and chunk-crossing spans retain the original byte/shift equation.
Single-byte loads retain their direct byte read. A remaining second-page suffix
proves the first span is below8 bytes, keeping its assembly shift below64.
Instruction-specific sign extension remains in the evaluator.

Tests independently assemble expected words for all four widths around chunk/page
boundaries, including unaligned and partial-word reads. They compare inactive/active
writers, frozen epochs, later overlapping writes and unchanged source aliases.
Constructor-only memory/writer temporaries remain alive through reads, and repeated
8-byte then narrow loads check zero extension. These cases join1000 balanced ARC
cycles. Existing full fault/permission/overflow ordering and public-step references
remain controls. A separate checked-release AddressSanitizer run of this source-owned
suite passes; it is additional local evidence, not a substitute for ownership proofs.
No public mutable backing, resource default, protocol byte or runtime check changes.


## Invocation-local scalar page windows, 2026-10-25

The independent scalar writer retains one readable page and two current-epoch
writable page headers. A successful original scalar preflight admits an exact
physical page tag; page permissions and sorted slots remain fixed for that writer.
Only valid widths 1/2/4/8 wholly within that page, outside the protected prefix and
below the existing exclusive-end overflow boundary can use a window. Width,
protection, overflow, cross-page and permission misses retain the original complete
preflight and Fault/Panic ordering. No page/chunk storage or mutation capability is
exported. The public API, protocol interpretation and default execution policy do
not change; all interpreters using the scalar writer share this implementation.

Writable headers enter a window only after successful first-write preparation.
Every cached store still runs the existing dirty-bit checks and prepares every
touched 512-byte chunk before mutation, including stores crossing a chunk boundary.
A retained writable header is already private, so this preparation cannot replace
that header during a borrowed cached access. Hits do not shuffle retained owners;
only successful single-page write misses rotate the two writable windows. Cloning
invalidates the readable owner before replacing storage. `snapshotMemory` clears
all three windows before publishing an immutable epoch, including calls through a
writer alias and unchanged epochs. Future writes therefore repeat COW preparation.
Window storage is fixed: three page-owner references and scalar tags/slots, with no
new retained chunk payloads or unbounded cache. Existing checked byte helpers stay
unchanged; assertions and bounds checks remain enabled.

`pvm_scalar_windows` compares the writer with immutable-memory operations across
valid/invalid widths, chunk/page crossings, low32 wrapping, protected and final-page
addresses, read-only/missing pages, failed-store atomicity, source aliases and saved
epochs. A second witness alternates writable state/stack pages and a read-only
table, forces writable-window eviction, and checks every saved page byte and
permission. One thousand complete working-set ownership cycles return to baseline.
Run `make unit SUITE=pvm_scalar_windows`; existing scalar-writer, chunk, machine,
prepared/step and host-memory/reference suites remain controls. A compiler privacy
witness rejects direct extraction of a writable window from the public writer.

### Local measured design evidence

Before promotion, three isolated local trials compared the accepted runtime with
this independent implementation on an Apple M1 Max arm64, pinned Nimony 4724f66c,
checked ARC/Clang 21 release/speed with ThinLTO. Pinned Rust PolkaVM 69e5b87c used
the public-API reused-instance adapter. Each trial ran all seven maintained
guest/size cases in both process orders, thirteen calls per process: three warmups
and ten measured calls. The final trial rebuilt both endpoints through identical
compiler source/cache/output paths using fresh private caches, and a repeated
candidate build produced a byte-identical image. All registers, gas, terminal
state, page bytes/permissions and source snapshots passed; deliberately wrong
expected gas was rejected before a successful timing row. Earlier single-readable/
single-writable chunk and page trials regressed minimal and were discarded.

CPU milliseconds below are forward / reverse process-order reused medians.
Ragnarök reuses the prepared-program owner but constructs fresh invocation memory
staging inside each execution. Rust input reset stays outside its execution clock;
these are execution comparisons, not total lifecycle parity or Linux CI evidence.

| Guest | Accepted prepared | Three-window prepared | Rust interpreted, reused |
| --- | ---: | ---: | ---: |
| Pinky | 202.114 / 199.658 | 178.950 / 176.601 | 94.798 / 94.744 |
| Sieve 100,000 | 6.059 / 6.077 | 5.759 / 5.831 | 3.560 / 3.626 |
| Minimal 100,000 | 13.802 / 13.822 | 11.552 / 11.645 | 6.020 / 6.128 |
| Memory fill 100,000 | 6.494 / 6.491 | 6.395 / 6.395 | 3.971 / 3.968 |

The paired CPU reductions are 11.46–11.55% Pinky, 15.75–16.30% minimal and 4.05–4.95%
sieve. Fill's 1.48–1.52% change remains unproven. No hardware instruction/branch/cache
counters were collected. Separate clock-disabled diagnostic copies show minimal's
software-window read misses falling from 400,000 to 1 and write misses from 200,004
to 2 per call; the original loop alternates table, writable state and stack pages.
These software counts describe window behavior, not hardware cache/branch misses.
Every prepared-cache observation matches the baseline, including eviction churn.
The retained interpreter remains about 1.6–1.9 times reused Rust CPU time here.

The measured source SHA-256 is `9bad399ed8745671ae3f1fafa80034c52de8da634097b30a2a7d91631a7ec916`
for `src/pvm/machine.nim`; promotion changes only formatter padding before one
field comment, preserving all tokens and line positions. Its promoted source
SHA-256 is `fb2208667897b137a828c82f4822f04b8b425e8902b3424c3ddd2406bffc7e62`. The local
record `build/pvm-port-lab/SCALAR-WINDOW-REPORT.md` retains constructor/cold timings,
all policy comparisons and sample ranges. Adjacent trial JSON/logs, immutable
source snapshots, generated C and `scalar-window-evidence-manifest.json` retain
exact source/binary identities. Those ignored artifacts and the translated
learning experiment are not shipped with this feature.


## Constant scalar writer widths

`load[Width](writer, address)` and `store[Width](writer, address, value)` accept the
same writer identity and guest addresses as their runtime-width overloads. Width must
be the compile-time constant 1, 2, 4 or 8; the supported-width precondition rejects
other constants during compilation. Runtime-width calls retain typed `InvalidWidth`
failures and the existing owner/width/permission/endpoint error ordering.

Both surfaces use the same private implementation. The constant only exposes an
already known byte count to the compiler: complete owner, low-32-bit address,
protected-prefix, exclusive endpoint, page permissions and cross-chunk/page checks
remain in place. Writable windows still prepare touched COW chunks before mutation;
readable windows still retire when their epoch changes. No mutable page/chunk view
or host address escapes. Ordinary interpreter and immutable snapshot access keep
their existing paths; prepared memory handlers carry their genuine static width
through invocation staging to these writer calls.

The scalar-window suite exercises all four constant widths against immutable
execution across nil owners, protected/wrapped/physical endpoint addresses,
chunk/page edges, read-only/missing pages and three aliased snapshot epochs. Both
constant-invalid load/store probes require the exact checked-precondition error.
The prepared suite retains all 139 opcode families, faults, host suspension, budgets
and lifetime checks. Performance qualification is recorded in
[pvm-prepared-blocks.md](pvm-prepared-blocks.md).
