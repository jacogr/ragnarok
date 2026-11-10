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

| Capability | Former ARM64 implementation | Former x86-64 implementation | Initial shared path and migration obligation |
| --- | --- | --- | --- |
| Pure register operations | Resident guest lanes with live-in and dirty masks | Canonical array access, with separate resident-access support | Copied pure spans exist on both. Preserve all register aliases and exact arithmetic while improving allocation independently. |
| Conditional block control | Immediate/register branch suffixes | Immediate/register branch suffixes | The shared self-loop uses unsigned less-than. The three-header loop adds exact immediate inequality, signed less-or-equal and register signed less-than edges. |
| Connected pure regions | Two/three-block cycles | One/two-block regions, with additional restricted prototypes | Shared single-block and bounded three-header register loops use exact weighted accounting and checked side exits. General connected control remains open. |
| Indirect scalar reads | All seven width/sign forms, prefixes and transactional bodies | A narrower retained read path | Shared bodies admit U8, S32 and U64 under restricted geometry. Extend the shared operand and refusal contract for the remaining applicable forms on both ISAs. |
| Direct-address reads | Direct loads with pure suffix/control lowering | No equivalent retained frame adapter | Checked only. Represent genuine decoded memory operands in copied IR before adding either public native path. |
| Mixed memory and register blocks | Mixed load/store bodies, guarded groups and precise partial exits | Narrower child/cycle prototypes | Checked only. Migrate loads, stores, arithmetic and control together with precise fault, quota and dirty-page effects. |
| Dirty store loops | Byte/word loops and grouped stores | Checked loop fusion and separate sealed native-child proofs | Checked fusion exists, but no shared native store kind. Require actual native stores and immutable publication on both architectures. |
| Read/store/tail cycles | Linked and resident cycle drivers | Restricted source-sealed cycle prototypes | No shared cycle kind. Retain useful source geometry and accounting without retaining synchronous compiler governance. |
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

The initial session retains one image, while the runtime's four registration credits cover idle,
deferred, queued, running, installed and retiring owners. These are deliberate initial limits,
not a general adaptive region cache. Whole-invocation eligibility does not prove that the first
materialized pure prefix is profitable. Future multi-region admission must separate candidate
evidence, source identity lifetime, outstanding compilation capacity and installed-code budgets.
Increasing the constants alone does not establish useful coverage or fairness.

The first bounded selection change preserves a qualified read nomination across an occupied
compiler work slot. Retention must not rescan an already emitted stream, create a readiness wait,
relax the existing successful-call eligibility, or alter loop/read/pure precedence. Retry must
revalidate the complete copied geometry, operations and optional continuation against the current
source and epoch. Pending and ready requests remain immutable. Invalidation, close and final drop
must leave no stale nomination or executable authority. The single finish-lock boundary introduced
by PR #2032 remains intact.

Production runtime wiring is a separate integration obligation. Full-state accumulation currently
binds a runtime; authorization, package refinement and inner-machine construction also have
runtime-less routes. Requested JIT may truthfully finish interpreted on those routes. Expanding
coverage requires an explicitly owned execution environment and bounded retention across consumers,
not a global runtime or an implicit compiler thread per program.

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
The private wide-parent refusal hook still creates a legacy code owner for its witness. It uses
the exact checked charge and dirty-loop handlers to seal its source.

The direct x86-64 region lowerer, publication and bridge still support the native shape, capacity,
retained-leaf and refusal witnesses. The raw probe exhaustion control and real owner counters
remain available. Generalized two-block control and mixed stores remain shared migration gaps.

## ARM64 pending branch retirement

The former ARM64 pending branch handler had no installer. Its private branch and dirty-loop
promotion paths were the only users of the frame's six raw and clipped memory descriptors.
Frame preparation and reuse no longer build those descriptors. The shared runtime still builds
its own current-invocation read and writable capabilities.

The independent three-block checked shape can still reach the legacy connected probe when a
private witness supplies an old ARM64 owner. The raw ARM64 branch, region and dirty-store
emitters and their native witnesses remain. General connected control and mixed-store coverage
still require equivalent shared ARM64 and x86-64 qualification.

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

## Remaining legacy admission witnesses

The old ARM64 three-block probe and x86-64 cold wide admission are built only with their
existing witness owners. Ordinary checked dispatch has no synchronous admission call and
keeps no pending candidates or original-handler table for those paths. The native witnesses
still exercise legacy publication, refusal and checked continuation under their explicit flags.

## Initial disposition

This contract records the migration architecture and required evidence. It does not qualify a new
native region, clear a held interpreter or cleanup PR, or establish a performance improvement.
The first selection fix and later capability ports record their observed results in their owning
feature contracts. Combined-source integration requires its own affected consumer qualification;
results from independent interpreter and JIT candidate trees do not qualify their composition.
