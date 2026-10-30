# Checked byte-loop word projection

The checked interpreter can keep a genuine `198 / 120 / 149 / 149 / 171` self-loop resident
without returning through ordinary dispatch. This increment recognizes the narrower dataflow
that extracts four successive bytes from one low 32-bit word. Four fully executable source
iterations can publish their equivalent checked four-byte store and final CPU state together.
No guest address, program identity or benchmark name selects this transformation.

The normative behavior remains the pinned Gray Paper and the approved
[memory ordering](pvm-polkavm-memory-order.md) exception. Opcode 171 is the full-width `!=`
branch. No protocol interpretation, dependency pin, public API, frame field or native ABI changes.
This extends [checked store loops](pvm-checked-store-loop.md) in both checked interpretation and
the optional ARM64 native emitter. Complete price plans, lazy memos and nonmatching dataflows
retain their established path. x86 native lowering remains future work.

## Source proof and runtime admission

Only an already validated true self-arm can select the word worker. Five roles are distinct:
source data, shift counter, byte destination, address counter and branch bound. The prefix
is logical right32(data,shift) into the exact byte-store value register; the two original
self-updates increment the address by 1 and shift by 8; the original `!=` compares that address
to the unchanged bound. Other aliases, strides and arm directions retain the scalar worker.

Before the first mutation, a batch requires 20 source attempts, safely representable four-block
pricing and enough gas (only three new charges when the first block is already paid), shift
modulo 32 equal to 0, a nonwrapping full-width address increment by 4, and address+4<=bound.
The first three original branch comparisons therefore cannot equal the bound. The fourth
comparison still uses the genuine cached predicate and may either continue or exit.

The effective store address must additionally satisfy the original conservative four-byte
fast-store range and a complete contiguous writable/stack extent. This read-only positive
proof intentionally matches `flatStore[4]`, which repeats the extent check and owns the actual
write and dirty-page accounting. No failed span is collapsed into an atomic word attempt:
the original byte loop must preserve earlier valid bytes and register prefixes before any
later fault. Missing, protected, fragmented, RO, wrapping or uncertain spans decline untouched.

Success writes the original low 32-bit word in the existing little-endian memory representation,
sets the byte destination to(word>>24), increments the full-width address by 4 and shift by32,
subtracts exactly 20 attempts and four original prices (or three when prepaid), and records the
last original five-instruction reservation. The original branch selector resets paid state.
There is no host, quota, gas or failing memory boundary inside the positively proven group;
partial groups retain every original addressable source node and worker.

Only sealed code coordinates persist in the exclusive stream. No word, register, writable
pointer or invocation snapshot is cached. Reset, accepted host epochs, published observations
and stream transfer continue through the existing ownership/publication boundaries.

## ARM64 native execution

The native dirty-loop emitter uses the same sealed role/stride/true-arm proof. Its additional
word path requires twenty attempts and four affordable block prices on an unpaid native entry,
a nonwrapping full-width base+4 no greater than the unchanged bound, and shift modulo 32=0.
The effective four-byte span must be aligned, within a fresh captured writable/stack descriptor,
and entirely on one already-dirty physical page. It never marks a clean page. Every declined
word guard restores borrowed gas/attempt/context registers and enters the established native
byte loop before any current-group mutation; first touch still reaches the original checked store.

Success emits one little-endian `STR Wsource`, the exact final byte/address/shift register
projection, four original prices, twenty source attempts and four completed source blocks. The
fourth original `!=` condition still selects the genuine exit or the next group. Guest registers
and software accounting are published through the existing eight-word call context. Previously
reserved context word 3 counts native word groups; descriptor/bitmap pointers remain borrowed
only for that one call. No guest word or invocation pointer is retained by the executable owner.
Existing fragment limits, reserved connected-region slot, arena move/destruction and W^X lifecycle
remain unchanged. Apple-reserved X18 is not used.

The maintained ARM witness adds 698 original gas/partial/fault/bound/shift cases and 110 actual
alias declines, including a positive aligned word group before a later readonly/missing-page
fault. Native word/owner/boundary/alias receipts are mandatory in both synthetic positive fixture
families. Missing, duplicate, malformed or refused-native activity cannot qualify; production
guards remain strict. Normal and forced-refusal witnesses plus the revised checked suite pass
locally on the combined source. An earlier private word-store suppression mutation independently
proves the new native path affects published bytes rather than only a coverage counter.

## Verification and local assessment

The existing `pvm_stream_checked_store_loop` suite retains its entire scalar-loop corpus and
adds a distinct word dataflow. Repeated public `stepOnce` is an independent dispatch oracle:
single-instruction plans cannot select either whole-block worker. Literal bytes 78/56/34/12,
poisoned destination values, partial/gas/prepaid fences, every source boundary, actual role
aliases, source/address carry, high full-width bounds, shift wrap, encoded offsets, top pages,
RW/RO/missing cross-page prefixes, transferred streams and accepted host epochs protect the
projection. Suppressing only the bulk word store must compile and fail the independent complete
page comparison while scalar/oracle stores remain intact.

The ignored preliminary proof passes 1,616 combinations/cases in ordinary and ARM-native-built
interpretation, plus its intended mutation. A possibly contended first DOOM cohort is retained
for correctness only. The quiet repeat uses byte-identical admitted images, frozen reference
inputs and a shared local measurement lock. No x86 or Linux claim follows from this prototype.

Local macOS ARM, 13 samples/process with 3 warmups excluded, raw CPU milliseconds forward/reverse:

| Public policy / phase | Parent | Candidate | Candidate / parent | Candidate / PolkaVM interpreted |
| --- | ---: | ---: | ---: | ---: |
| Interpreter init |317.0655 /316.8205 |314.7695 /315.8505 |0.99276 /0.99694 |0.46924 /0.47130 |
| Interpreter tick |30.6515 /30.7135 |25.2055 /25.1955 |0.82233 /0.82034 |0.57367 /0.57189 |
| JIT init |175.391 /175.570 |175.8445 /175.8465 |1.00259 /1.00157 |0.26214 /0.26239 |
| JIT tick |21.4185 /21.1975 |21.365 /21.430 |0.99750 /1.01097 |0.48626 /0.48642 |

Twenty quiet full-state/event DOOM processes pass; build/assertion controls are reused only
for their byte-identical images and explicit previous receipt. Fifty paired micro processes
and two new assertion negatives pass. Long-sieve JIT is 0.61–0.67% higher locally; interpreted
memset 0.26–0.61% higher. Other micro results are small/mixed, with native Pinky 0.75–0.90% lower.
The ~18% local interpreted tick gain is relative to the measured parent worker, never added
to earlier separately measured results. Six affected Make/Hastur suites, final native-enabled interpretation and the intended
missing-bulk-store mutation pass on the production source, retaining the entire scalar corpus.
Exact-head Linux ARM assessment remains pending. Evidence: `build/pvm-checked-word-loop/{proof,doom,micros}`.

## Private native composition evidence

The partner's separately admitted native prototype was composed onto checked layer 59dfedfd.
Five order-rotated public DOOM tick candidate/parent CPU ratios are .91229,.91655,.91279,.91149
and .91263 (median .91263). Init has zero word groups and mixed ratios, median 1.0021. A direct
DOOM observation records 255728 native groups, separately from timing. Three paired micro controls
show preliminary upward costs 1.68% minimal100000 and 1.02% long sieve; Pinky ratio .9960, with zero
word groups and unchanged native code/call counts in those micro guests. These are local macOS
ARM prototype results, not a final production/Linux or combined additive claim. The final cohort
must measure both public policies against one explicit latest-master baseline after all source
and test changes. Native evidence is preserved in the partner's ignored
`build/ci/arm-word-batch-prototype` directory.
