# Shared asynchronous JIT capability migration

## Scope and authority

Migrate applicable capabilities of the former synchronous ARM64 and x86-64 frame compilers into
the shared asynchronous execution path, then retire their old admission, cache and dispatch paths.
The reference implementation inventory is master `d0262a43a696aa9fd4ddb45cd5dc6f1f7595b491`;
the initial shared runtime baseline includes `1eefb86b92b8e87e39cc07d0e0049590fbc88694`.
This is an implementation migration. The pinned Gray Paper, instruction semantics, unsigned gas,
source attempts, fault ordering, host behavior and snapshot ownership remain authoritative through
the existing [execution](pvm-execution.md), [handler-stream](pvm-handler-stream.md),
[machine](pvm-machine.md) and [shared runtime](pvm-shared-async.md) contracts.

Both maintained ISAs must implement the same admitted semantic capabilities. Encoding, immediate
selection, register allocation, spill layout, branch reach and executable-memory publication are
platform responsibilities. Candidate selection, eligibility, resource policy, copied source
certificates, scheduling, cancellation, collection and checked fallback belong to the shared path.
An architecture-specific speed result is not evidence that the other architecture has a capability.

The matrix below records source capabilities and migration gaps at the initial baseline. A legacy
emitter or internal frame witness is not evidence of reachability through the public prepared owner.
Current public preparation starts with the checked layout; native execution requires an explicitly
bound runtime. Unported capabilities remain checked until their real shared path is qualified.

## Capability inventory

| Capability | Former ARM64 implementation | Former x86-64 implementation | Shared coverage and remaining migration obligation |
| --- | --- | --- | --- |
| Pure register operations | Resident guest lanes with live-in and dirty masks | Canonical array access, with separate resident-access support | Copied pure spans exist on both. Preserve all register aliases and exact arithmetic while improving allocation independently. |
| Conditional block control | Immediate/register branch suffixes | Immediate/register branch suffixes | The shared self-loop uses unsigned less-than. The three-header loop adds exact immediate inequality, signed less-or-equal and register signed less-than edges. |
| Connected pure regions | Two/three-block cycles | One/two-block regions, with additional restricted prototypes | Shared single-block and bounded three-header register loops use exact weighted accounting and checked side exits. General connected control remains open. |
| Indirect scalar reads | All seven width/sign forms, prefixes and transactional bodies | A narrower retained read path | Both ISAs admit all seven scalar width/sign forms within the [shared read-body geometry](../src/pvm/internal/native_read_body.nim). General memory/control composition remains open. |
| Direct-address reads | Direct loads with pure suffix/control lowering | No equivalent retained frame adapter | Both ISAs admit direct-address scalar loads within the same [source-certified read bodies](../src/pvm/internal/handler_read_body.nim). General direct-memory regions remain open. |
| Mixed memory and register blocks | Mixed load/store bodies, guarded groups and precise partial exits | Narrower child/cycle prototypes | Both ISAs share bounded [read/store cycles](../src/pvm/internal/handler_read_cycle.nim) and [mixed self-loops](../src/pvm/internal/handler_mixed_loop.nim). A bounded [static graph](../src/pvm/internal/native_fusion.nim) can also use the paid-memory continuation ABI. |
| Dirty store loops | Byte/word loops and grouped stores | Checked loop fusion and separate sealed native-child proofs | The [shared loop certificate](../src/pvm/internal/handler_mixed_loop.nim) admits a transactional byte store or two ordered paid read/store groups with scalar stores of 1, 2, 4 or 8 bytes. Other store sequences remain checked. |
| Read/store/tail cycles | Linked and resident cycle drivers | Restricted source-sealed cycle prototypes | Both ISAs share the [seven-role connected cycle and exact receipt](../src/pvm/internal/native_read_cycle.nim). General connected graphs and additional native entry headers remain open. |
| Larger connected control | Linked/resident macro routes | Restricted wide-source prototypes | Checked only. Evaluate demonstrated dynamic regions and use bounded shared graph certificates; fixture-specific nomination is not a production policy. |
| Arena and ABI mechanics | ARM word publication, coherency and saved-register rules | x86 byte publication, mapping and SysV rules | Shared exclusive images and lifetime certificates exist. Keep the required mechanical lowerers and independent ABI proofs when deleting old frame adapters. |

Historical shapes are evidence for candidate ports, not an obligation to preserve their exact
source recognizers or old scheduler. Each proposed port must identify its applicable behavior,
production workload, current shared gap and replacement representation. An obsolete or superseded
shape needs an explicit disposition rather than silent deletion or a fabricated native receipt.

## Shared ownership and execution boundary

Immutable source facts belong to the prepared identity; mutable stream offsets and native patches
belong to its exclusive execution lease. Original source PCs, source fact ordinals, emitted node
offsets and native image coordinates are different namespaces. A retained plan pointer, node count
or geometrically complete suffix alone cannot establish original complete-block authority.

Compiler requests contain bounded copied IR and registration, generation, ticket and stream-epoch
certificates. They retain no Program, frame, guest memory, register values, host context or callback.
Only the compiler emits and publishes executable storage. The caller validates and installs a
completed image at an ordinary exclusive boundary without waiting for compiler readiness.

Region entry must establish the exact paid reservation, remaining attempt budget and memory
capabilities needed by that image. A region with multiple priced blocks must debit each complete
visit correctly and return an explicit continuation for partial quota, insufficient gas, fault or
host boundaries. A guard refusal before effects may execute the original checked body. A failure
after committed effects must not replay those effects through fallback.

Native stores must update bounded dirty membership for every changed physical page, including
cross-page operations. Full access and permission preflight precedes an atomic scalar store.
Snapshot publication and host observations retain independently owned immutable bytes. Fresh
invocation or host-replacement storage supplies fresh borrowed descriptors; executable code and
compiler jobs never retain them.

## Selection and resource work

The [shared scheduler](../src/pvm/internal/native_pipeline.nim) owns image credits and selection.
[#2122](https://github.com/jacogr/ragnarok/pull/2122) added a bounded exception to the initial
single-image policy: one hot later Read can replace an unused image per stream epoch.
General region expansion, fairness and aggregate retention remain separate work.

The first bounded selection change preserves a qualified read nomination across an occupied
compiler work slot. Retention must not rescan an already emitted stream, create a readiness wait,
relax the existing successful-call eligibility, or alter loop/read/pure precedence. Retry must
revalidate the complete copied geometry, operations and optional continuation against the current
source and epoch. Pending and ready requests remain immutable. Invalidation, close and final drop
must leave no stale nomination or executable authority. The single finish-lock boundary introduced
by PR #2032 remains intact.

The [Services owner](../src/app/services.nim) records production runtime wiring and the required
environment contract before extending it. Accumulation residency and managed package completion
share its runtime. Authorization, inner modules, and the JAMNP-S audit/work-sharing adapters have
runtime-less execution routes. Four installed accumulation images can deny a package compilation
credit even with no active invocation. Checked fallback is expected at that bound; fairness is
not implied. Per-owner idle memory ceilings do not establish an aggregate prepared-storage bound.
Future wiring requires explicit ownership/shutdown, aggregate retention budgets and a competition
policy across the existing consumers before increasing availability or image capacity.

## Bounded mixed store loops

Both shared native backends can run source-certified transactional and paid mixed self-loops
beside a connected Read image. The [source certificate](../src/pvm/internal/handler_mixed_loop.nim)
owns accepted geometry and bounded discovery; [worker and image ownership](../src/pvm/internal/native_pipeline.nim)
owns the single global auxiliary arena and exact primary-ticket/proof-set authority.
[Publication](../src/pvm/internal/native_platform.nim) preserves ranked slots within the common
byte cap; target encoding sizes can leave different slots checked on each ISA.
The shared-async native suites cover source admission, primary priority, publication accounting,
quota-bound handler restoration and borrowed retirement.
The [mixed arena qualification](../tools/pvm_native_ci.py) also checks the exact executable bytes,
aligned entry offsets, code cap and image move on the native host. Its two refusal builds verify
that the publisher releases the arena when the first or second append fails. The publisher
reports the failing slot after checking the unmap, and the second-slot run also requires a
successful first append. The paid emitter also reserves its instruction, fixup and scratch
storage before emission. The recoverable heap-cap control requires an empty image on refusal
and a successful retry with the same certificate.

## Bounded static fusion

A ready low-coverage pure prefix can train one long checked segment per stream epoch.
A sparse sample table ranks up to 128 independently source-certified blocks. An optional
worker image links only already resolved original jumps and branch arms, with at most
128 KiB of published code and eight original reservations per native entry. A compatible
linked image borrows the runtime's existing optional credit while retaining the incumbent
prefix. Connected Read, register rings and their mixed-loop images use their existing routes.
The [stream bridge](../src/pvm/internal/handler_fusion.nim) accounts for the exact block
path and preserves paid continuation at the first refused memory operation.

The shared native suites exercise a live two-header graph, cold admission, reserved-source
quota, out-of-gas ordering, a paid read fault after a store, and repair through the same
prepared owner. Unsupported terminals and memory extents retain the checked handlers.

## Qualification and retirement

Every port carries one coherent implementation, supporting VM witnesses and feature-record update.
Its acceptance evidence must name the exact source, toolchain, dependency pins, build profile and
native host. Linux ARM64 and Linux x86-64 qualification are authoritative. Local Mac ARM experiments
are initial evidence and use an exclusive timing window coordinated across the PVM group.

Required witnesses follow the capability rather than merely its helper names:

- Actual native work through a runtime-bound public prepared owner on each ISA, with complete
  CPU, unsigned gas, PC, paid-state, memory, permissions, original-source and host-event checks.
- Literal positive controls for the migrated shape, both control directions and relevant operand
  aliases, plus zero/partial/full quota, unaffordable block and protected/cross-page fault cases.
- Immutable earlier observations, host repair/reentry, changed input memory and reused-owner
  execution. Raw encoder/image/ABI proofs support these checks but do not replace them.
- Allocation/publication refusal and bounded resource admission, original checked continuation,
  source-epoch invalidation, queued/running cancellation, close and physical image retirement.
- Applicable cold and reused canonical full-invocation performance on both architectures, with
  adverse or mixed results given an explicit disposition. A code deletion or native-operation
  count is not itself a speed result.

The canonical performance producer and its maintained parsers remain the measurement path.
Retain original failed attempts, both CPU and wall observations, source/role orders and cold,
warmup, reused and cumulative-prefix results. Supplementary coverage and phase diagnostics must
not replace the enclosing invocation score, subtract components, force native readiness or select
only favorable calls. Repeated frozen DOOM ticks establish a controlled workload; changing-input
and continuing-frame checks are separately needed to assess broader region reuse.

Retire a former frame/compiler path only after its applicable capabilities have migrated or have
an explicit retirement disposition. Remove obsolete entry points, caches, policy branches and
witness adapters together. Preserve mechanical ISA encoders, arena ownership and ABI tests that
still serve the shared lowerers. No native capability is considered migrated solely because its
old fixture now passes through checked fallback.

## x86-64 pure-region frame retirement

Prepared programs start with a checked plan and empty stream. A runtime-bound owner reaches
native code through the shared session. The former x86-64 pure-region frame probe had no
installer, and its whole-block and connected handlers were reachable only from that probe.
The direct x86-64 wide publisher witness seals the exact checked charge and dirty-loop source
and creates its own raw code owner, without patching the frame.

The direct x86-64 region lowerer, publication and bridge still support the native shape, capacity,
retained-leaf and refusal witnesses. The raw probe exhaustion control and real owner counters
remain available. Generalized two-block control and mixed stores remain shared migration gaps.

## ARM64 pending branch retirement

The former ARM64 pending branch handler had no installer. Its private branch and dirty-loop
promotion paths were the only users of the frame's six raw and clipped memory descriptors.
Frame preparation and reuse no longer build those descriptors. The shared runtime still builds
its own current-invocation read and writable capabilities.

The independent three-block checked shape later moved to shared register-loop admission. The
raw ARM64 branch, region and dirty-store emitters and their native witnesses remain. General
connected control and mixed-store coverage still require equivalent shared qualification.

## Shared three-header register loop

The [copied certificate](../src/pvm/internal/native_register_ring.nim) admits complete original
`200/139/82 → 131/88 → 151/152/173` blocks with one closed successor and one resolved checked
exit per block. Admission follows a real closed checked round. The [stream binding](../src/pvm/internal/handler_register_ring.nim)
copies decoded operations, both marked successors, and original prices. Every ready lease matches
that certificate against its restored stream. Entry supports all three rotations under the existing
worker, image ceiling, and registration credits.

Every native block checks the whole source quota and the unsigned original gas charge before debit.
A failed guard returns to the exact unpaid checked header. The original worker still owns partial
prefix execution and the zero-attempt and out-of-gas ordering. The entry wrapper verifies per-role visits,
weighted gas and attempt totals, the connected visit order, and the final branch against the
committed register file.

The sealed DOOM init observed the three-header loop during its first checked invocation. Stock
selected a two-operation pure prefix and had no read nomination. The ring can supersede that bare
prefix while a certified self-loop or a retained read keeps its existing selection. Tick still
selects its connected read renderer. On macOS ARM64 each ready init call recorded 9,032 native
entries and 170,413,402 complete original attempts. Each ready tick recorded the stock 651 native
calls and 10,865,293 operations. These receipts count source work. The application oracle compares
gas, all registers, every mapped byte, and the complete host event stream.

The direct witness ran 1,728 cases on each native Linux ISA before runtime integration, including
all entry rotations, each external branch, zero and partial quotas, and full-width prices. Both
legacy direct region suites also passed. [Direct native CI](https://github.com/jacogr/ragnarok/actions/runs/42861336730)

## ARM64 synchronous region retirement

The shared register loop replaces the old three-header synchronous frame path. Its only legacy
owner initializer was a macro witness hook. The hook set a raw owner refusal flag while its
macro source executed through checked handlers. The frame and stream no longer retain a legacy
ARM64 owner or fallback handler table. The shared worker, checked histories, and charged
register-loop handlers keep their source and ownership contracts.

The [direct ARM64 publishers](../src/pvm/internal/arm64_jit.nim) still cover raw regions,
the five-word region ABI, capacity and refusal, and the distinct mixed-memory and macro ABIs.
The raw cycle witness still checks
that an overlarge resident image leaves the same owner available for linked publication. The macro
frame witness continues to check partial budgets and fresh checked stream reentry, with its receipt
identified as checked reentry.

## Remaining legacy admission witnesses

The x86-64 cold wide probe, pending queue, boundary admission and both frame installers are retired.
The checked frame and stream no longer retain a legacy x86 JIT owner. The seven checked source blocks
and outside exit in frozen DOOM init and tick match the source of the shared Read
image. Its installed x86-64 image enters at Read and covers Read, StoreSetup, Store, Tail, Jump,
Outer and Gate. The outside target remains checked. Each ready tick has 651 checked Gate
dispatches preceding the 651 native Read entries. The Read charges provide the original paid
reservation at entry. They do not represent additional checked Read execution. The x86 receipts
show 251 unpaid returns to Store and 502 checked four-byte Store groups per ready tick. In a
separate ARM64 trace all 251 unpaid Store returns came from a clean first dirty bit. Independent
native entry at Gate or at a checked Store continuation remains a separate capability question.
[Installed x86-64 image and receipts](https://github.com/jacogr/ragnarok/actions/runs/42853746772)

The [direct x86 publisher](../src/pvm/internal/x86_jit.nim) has its own tests for source-seal
negatives and checked histories. They exercise a parent refusal after a real dormant child
append, then a separate positive linked parent and child
with exact gas, attempts, complete memory and checked continuation. Raw image, ABI and capacity
controls retain their own profiles.

## Connected Store and Tail completion

The connected Read image now shares eligible Store and Tail completion by default.
The [ARM64 emitter](../src/pvm/internal/arm64_jit.nim) and
[x86-64 emitter](../src/pvm/internal/x86_jit.nim) own the lowering contracts.
The [shared entry suite](../tests/support/pvm_read_cycle_execution.nim) checks the original
role receipts and state. The qualified page-hit path fell from 82 to 75 instructions on ARM64
and from 68 to 54 on x86-64. [Linux qualification and paired evidence](https://github.com/jacogr/ragnarok/actions/runs/43011408267)

## Initial disposition

This contract records the migration architecture and required evidence. It does not qualify a new
native region, clear a held interpreter or cleanup PR, or establish a performance improvement.
The first selection fix and later capability ports record their observed results in their owning
feature contracts. Combined-source integration requires its own affected consumer qualification;
results from independent interpreter and JIT candidate trees do not qualify their composition.
