# Eager prepared PVM owners

Refs #1733. The landed shared and public policy interfaces are prerequisites. This increment
implements public adoption of a complete sealed source stream, copied construction observations,
and truthful actual-engine receipts. It changes neither the default `jit` policy nor pins.
The Gray Paper and existing program, memory, gas, execution and host contracts remain authoritative.

## Boundary and availability

`newPreparedProgram(source, limits, Compiled)` admits one immutable source plan under the caller's
existing limits and calls `prepareFlatStream(plan)`. The hook receives no guest memory, registers,
gas balance, attempt budget, host context or callback. No guest execution discovers preparation
work. Public storage is published only after successful source preparation and a valid sealed
receipt; all private partial stream ownership retires on refusal.

The shared hook on the prerequisite master remains an honest `NativeNotBuilt` stub. Ordinary JIT
build flags alone do not establish that the source-preparation facility is built. This consumer
continues returning `BackendNotBuilt` there. Private positive qualification may combine this public
layer with a separately identified real shared implementation; that evidence records both source
identities and does not certify the shared performance experiment or claim master execution.

The constructor requires `sealed=true`, candidate count equal to the admitted genuine instruction
facts, and a complete partition into native, checked and capacity-deferred entries. It checks
individual bounds before subtraction so a wrapped sum cannot authorize a fabricated partition.
An unexpected success with an unsealed or inconsistent receipt returns `BackendFailure` and no
usable prepared owner. Existing stage-sensitive error translation remains unchanged: malformed
caller source differs from a shared hook rejecting an already admitted plan. The default lazy
policies retain their existing error mapping.

## Ownership and invocation

The complete stream moves once into the existing non-copyable `PreparedStorage`. Public handle
copies share one immutable source identity and exclusive busy lease. The constructor retains no
invocation state. Existing source checks precede moving code into a fresh private frame; execution,
host suspension/resume, page repair, terminal replies and failure paths restore the same owner.
Same-owner callback reentry and diagnostic reads during the lease remain refused. Equal program
bytes do not confer the identity required to reuse an executable owner.

Construction admits native work only according to the shared generator policy. Unsupported entries
and native capacity deferrals retain complete checked handlers inside the same selected policy.
They do not substitute a different prepared backend. Fact/node/preparation admission failure is
a transactional typed refusal. Eager construction does not change dynamic pricing, charge a
block early, populate a caller's lazy memo or reject an unreachable entry solely for a future
pricing failure.

## Copied observations and actual receipts

`PreparedInfo.compilation: PreparedCompilationInfo` copies the source-entry partition and sealed
flag. `sourceEntries` counts genuine instruction PCs, including interior and folded-noop entries;
`nativeEntries` counts entries starting at native bodies, rather than native-covered instructions.
`checkedEntries` and `capacityDeferred` complete the partition. Lazy and foreign owners remain
zero/unsealed. The optional `pvmSourceSealingReceipt` field copies attempted compilation passes
for CI; ordinary builds contain no such field.

`nativeFragments` remains cumulative successful physical publications. `nativeCodeBytes` and
`nativeCompilationNs` copy executable occupancy and supplementary construction time; they are
not process RSS or a performance qualification. Sealed compilation, publication, stream nodes,
preparation units and code occupancy freeze across invocations. Native call and operation
counters remain live and are inspected only at existing publication boundaries.

Completed direct and host receipts report `compiled` only if that invocation executed native
operations under a compiled owner. Checked-only execution reports `interpreted`; existing native
JIT execution still reports `jit`. The selected policy name alone never claims native work.
Startup text states eager source admission is required; `backendAvailability` performs genuine
typed source preparation before application resources or guest/host work.

## Qualification scope

The public suite covers unavailable build/facility, unsupported host and executable-owner refusal;
immutable source/state; all source-entry and early attempt/gas prefixes; charged/fault retry;
host ordering/mapping/reentry/terminal/fallible response behavior; source mismatch; exact resource
boundaries and native-capacity deferral; frozen construction versus advancing execution counters;
and copy/move/ARC cleanup. Existing CLI and runtime consumers cover startup, strict spellings,
defaults, parser help and isolation from optional foreign selection.

Local verification is formatting, inventory and Nimony source-only checks. Linked execution and
native ownership qualification occur only on explicit Linux CI refs with exact source and build
identities. The suite can truthfully exercise a typed unavailable facility on the landed stub;
positive receipts require an actual sealed shared implementation and cannot be inferred from
ordinary native build flags or a passing unavailable-control run.

### Bounded private correctness receipt

[CI run 40903375793](https://github.com/jacogr/ragnarok/actions/runs/40903375793) passed Smoke and
both Linux architecture jobs at diagnostic `9e6cabd47288e209443466b77b85010b157ca3e0`. Runtime
`fc164c1b8488bd372ade074e1332a9e967c7c435` combines public source
`ccd2e63b93c2804664660c9115b87512232bc352` with exactly four shared files pinned from
`5719c065ec9fc037dfee739cc649cb66b905f7b6`: `handler_stream`, `arm64_jit`, `x86_jit`, `source_seal`.
The private diagnostic changes only the canonical workflow and its job inventory/identity tests.
Its 61 inert safeguards pass. This is explicit private integration evidence, not master execution
or shared implementation/performance acceptance.

Each architecture ran app/runtime/compiled suites in plain and native profiles, precise storage
and wrong-host refusals, and a positive-on-refused assertion control that failed as required.
Author raw-artifact audit rehashed all 18 actual retained ELFs, both original bridge libraries,
exact compiler/process logs and stdout, ARC/release/bounds/ThinLTO/native flags, eight copied ARC
observations of 1000 lifecycle iterations, and 673 tracked Git input hashes per host. The tracked
hash maps are identical across architectures and match exact runtime Git bytes. Original Rust ABI
tests passed (three per host). Compiler/Clang executable bytes were not retained; their hashes
remain provenance only. The ARC reporting helper is bound by Git provenance, outside the separate
before/after input manifest; its caller's lifecycle assertions are covered source and actual runs.

The ordinary public-source [Smoke run 40902323492](https://github.com/jacogr/ragnarok/actions/runs/40902323492)
passed on `ccd2e63b93c2804664660c9115b87512232bc352`. Subsequent evidence-only documentation does not
change these runtime/test/helper/pin/configuration inputs. Full continuing-DOOM and performance
qualification are not supplied by this bounded public-unit receipt. Independent final review
and separate shared implementation readiness remain required.

This increment does not close #1733. Complete native opcode coverage, broad compiled-engine
comparison and performance acceptance remain separate requirements. No rejected shared performance
result is relabeled as acceptance, and this feature adds no disk cache, cross compilation,
persisted code format, new lowering, native ABI change or default-policy change.
