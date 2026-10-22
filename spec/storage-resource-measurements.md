# Storage resource observations

## Scope and baseline

The next storage tranche begins at merged `18764f6252e6599ab6b1ddd1c6eb729c6c11a307`.
Nimony `5b51edfedb4d0dbd9028d9e57ac61d69dffe9410` and Gray Paper
`1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d` remain pinned. Before edits, the selected
`storage_growth_fixtures` native suite and 23 sustained report safeguards passed on this tree.
The previous thirty-layer stack is merged; its branches and ignored evidence remain preserved.

This first increment adds a bounded resource baseline before choosing deployment-scale or
paged-storage experiments. It changes no storage runtime, physical layout, defaults, state/app API,
checkpoint authority, recovery policy or documented M1 scope. Full protocol state serialization
remains incomplete. Existing Perf Storage speed and SDK reports retain their schemas and coverage.

## Measurement contract

`make bench-storage-resources` provisions through Make and builds the existing sustained fixture
with checked native ARC/Clang release optimization and LTO. Each invocation runs one complete
8,192/32,768-entry sweep trajectory with 64 four-key publications and 256-byte values. Memory,
synchronized journal and managed backends run in both opposite backend orders. Independent
full-map/history/reader assertions and strict restart/reclamation checks remain in the native
fixture. Native durations are validated then discarded, never pooled into speed statistics.

A fresh Python observer waits for exactly one direct native child. RUSAGE_CHILDREN records peak
RSS and minor/major faults, including any waited descendants. The observer's memory is excluded.
Darwin peak RSS is bytes; Linux KiB is explicitly converted to bytes. Other hosts refuse.
These are whole-process observations, including fixture construction, expected maps, validation,
held readers, restart and reclamation. They do not isolate repository memory, peak ownership at
one phase, disk-read counts, physical device I/O, cache eviction or power-loss durability.

OS cache policy is unchanged and recorded. Backend order is explicit, with matching physical
counters required across passes; fault and RSS observations need not match. Zero major faults
cannot prove a cold cache or establish absence of paging on another host. No resource threshold
relaxes correctness. Each child has a 300-second timeout, with its owned process group killed and
reaped on timeout by the existing command runner.

The report freezes source inventory, Git revision/dirty state, pinned toolchain, compiler and native
provider identities, checked build and execution argv, binary hash, host CPU/platform/page size and
start/end load. Source/tool/provider/executable drift refuses success. Artifacts are isolated under
`build/tests/storage-resources/`; failures remove successful summaries and retain failed JSON/logs.
Previous storage evidence directories are untouched.

## Completion checks and next work

Require strict one-sample parsing without weakening thirteen-sample speed coverage; reject missing,
reordered, malformed or boolean observations, unchecked builds, failed exits and physical-work drift.
Exercise the real observer positive control and failed-child stale-artifact refusal, then run the
new Make target on the merged baseline. Record host-specific observations without performance or
cold-cache claims. Larger fixtures and controlled paging/cache experiments remain subsequent work,
chosen from these measurements. Hardware power-loss qualification remains separately scoped.

## First local observations

On macOS ARM64, the new Make target passed its checked build and twelve native controls. The two
opposite backend orders had identical physical counters and peak RSS; minor faults varied. At
32,768 entries, whole-process peak RSS was 116.39 MiB for memory, 187.56 MiB for journal and
231.67 MiB for managed. Every observation recorded two major faults. These process-lifetime counts
cannot attribute faults to repository access or establish cold-cache behavior.

The next experiment should separate fixture/expected-map memory from storage-owner retention
before interpreting larger-state memory growth or choosing a physical layout. The current bounded
workload alone does not establish out-of-core performance. No runtime optimization was selected.

Local qualification includes the merged-tree native growth-fixture baseline, eight new resource
safeguards, all 23 existing sustained report safeguards, the resource Make target, verification
inventory, formatting and whitespace. The initial formatting setup hit a transient Rust mirror DNS
failure; the same Make check was retried. Exact inputs, commands, logs and source identities remain
under `build/tests/storage-resources/` and `build/storage-db3-*`. This is local macOS evidence on
an explicitly dirty source snapshot, not an exact committed-head or Linux CI claim.

## Live allocator checkpoints

Test-owned `occupiedStorageBytes` samples the pinned Nim allocator at explicit lifetime boundaries.
A repeated 16 KiB positive control observes live bytes then returns to its baseline after ARC
retirement. These current managed-heap observations exclude stack/native-library memory and OS
page cache, and are distinct from the fresh-child whole-process peak RSS observations.

The `storageAllocationPhases` build emits live allocator checkpoints after fixture preparation,
seed capture, backend initialization, publication, reader acquisition, extraction, reads, available
strict reopen/reclamation and final owner close. It requires one sample and excludes SDK observation.
Ordinary speed builds compile these checkpoints away. Closed checkpoints deliberately retain the
held views and fixture, making the observed ownership boundary explicit rather than claiming a
fully released process.

Allocator output admission requires the exact available phase order followed by one fully validated
native trajectory. Missing, duplicate, reordered, late, negative, noncanonical or overflowing
checkpoints refuse. Backend and workload substitution still fail the existing native parser.
Allocation rows carry current Nim heap bytes and physical counters only; all duration values are
discarded after validating the native witnesses.

## Bounded resource panels

Shared resource-panel orchestration retains exact native commands, source-owned cases, raw stdout,
parsed observations and fresh-child counters. It reparses raw witnesses before final rendering,
checks all covered source/compiler/provider/binary identities at both ends, and atomically publishes
success only after complete coverage. Build, timeout, native assertion, parsing or rendering failure
removes stale public summaries while preserving diagnostic receipts. Each future panel owns its
case plan and parser; orchestration never infers semantic success from exit status alone.

`make bench-storage-allocations` runs the separate allocator build at 8,192/32,768 entries and 64
sweep publications in both backend orders. Its JSON retains raw native witnesses and whole-child
resource counters; Markdown reports current managed-heap bytes per boundary. Opposite-order
physical work must match. Differences between boundaries describe the complete live object set,
not isolated repository sizes, and independent process peak values must not be subtracted.

## Fixture-only retirement control

A separate lifetime workload returns only scalar observations from an isolated prepared-fixture
scope. It checks all 64 prepared successor roots and final read-address cardinality, then requires
actual allocator equality after every graph owner retires. Unperformed owner/reader stages carry
`-1`, not fabricated zero usage. This supplies a fixture control without subtracting unrelated RSS
peaks or allowing fixture graphs to remain alive in subsequent storage-owner measurements.

`make bench-storage-lifetimes` admits fixture-only control rows at 8,192/32,768 entries, requiring
all prepared-root checks and exact baseline equality after scope exit. Its raw witnesses and
fresh-child RSS/fault counters remain in a separate artifact directory. Reports do not infer
repository memory by subtracting peak values from independently running processes.

The `owner` lifetime scenario constructs the same 64-publication memory repository inside a helper,
then retires all prepared fixture graphs before observing it. Full-map validation still checks every
key/value and local generation. No immutable reader escapes; ordinary close and scope exit must
both return the allocator to the exact baseline. Its owner bytes are therefore measured directly,
not estimated by subtracting separate process peaks.

### Reader lifetime

One immutable snapshot retains its exact complete map after owner close and releases at scope exit. Fixture graphs retire before the owner checkpoint. Native validation covers
the retained values after owner close, and every scope must return to its exact allocator baseline.
Current managed-heap observations remain distinct from peak RSS and OS page-cache behavior.

### Readers lifetime

A bounded 4096-snapshot vector shares one graph and keeps every exact root/generation alive after close. Fixture graphs retire before the owner checkpoint. Native validation covers
the retained values after owner close, and every scope must return to its exact allocator baseline.
Current managed-heap observations remain distinct from peak RSS and OS page-cache behavior.

### Extraction lifetime

Complete-map extraction owns independent key/value payloads that remain valid after physical owner retirement. Fixture graphs retire before the owner checkpoint. Native validation covers
the retained values after owner close, and every scope must return to its exact allocator baseline.
Current managed-heap observations remain distinct from peak RSS and OS page-cache behavior.

### Lookups lifetime

4096 spread public record copies retain their full independent payloads after source close and fixture retirement. Fixture graphs retire before the owner checkpoint. Native validation covers
the retained values after owner close, and every scope must return to its exact allocator baseline.
Current managed-heap observations remain distinct from peak RSS and OS page-cache behavior.

### Selection lifetime

An opaque selected-root plan retains its exact immutable source and permits a complete independent clone after close. Fixture graphs retire before the owner checkpoint. Native validation covers
the retained values after owner close, and every scope must return to its exact allocator baseline.
Current managed-heap observations remain distinct from peak RSS and OS page-cache behavior.

## Exported lifetime witnesses

The isolated-lifetime panel exports every available checkpoint, explicit `-1` sentinel and child
RSS/fault counter in `lifetimes.csv`. Rendering reparses the same raw native rows. Source-owned
extra artifacts cannot escape the panel directory or overwrite its result/summary. Any late export
failure retires every public success artifact while retaining failed JSON and the originating log.
The summary shows owner, held and closed boundaries separately so retained readers and copied
payloads cannot be mistaken for the same ownership behavior.

## Cache and environment provenance

Resource panels record start/end output-filesystem geometry, capacity/available bytes, numeric
filesystem device identity, physical RAM when observable, and inherited address-space/data limits.
Unavailable capacity stays explicit. Recorded limits are not changed and do not claim enforcement.
Cache policy explicitly remains unchanged; neither filesystem metadata nor low page-fault counts
establish eviction, disk-device activity or an out-of-core workload.

## Per-file cache advice

A test-owned regular read-only descriptor may request Linux `POSIX_FADV_DONTNEED` or Darwin
`F_NOCACHE` through their actual exported host interfaces. The result records requested,
unsupported or refused distinctly; none asserts eviction or cold storage. No global cache drop,
namespace change, write operation or production storage hook is introduced. The unchanged policy
makes no request. Descriptor admission and file-byte preservation have real-file positive controls.

`make bench-storage-file-cache` synchronizes exclusive16/64 MiB synthetic files in the parent, then
runs fresh read-only Python children in opposite unchanged/hinted policy orders. Every byte and the
complete digest are validated with bounded64 KiB buffers and strict short-read progress. Symlinks,
size/content changes and identity changes refuse. Logical read calls and read-interval page faults
include validation work; child peak RSS excludes parent preparation but includes Python startup.
Requested advice is never labeled eviction, cold storage, throughput or physical device I/O.

## Validated resource comparison

`tools/compare_storage_resource_panels.py` compares allocation/lifetime/deployment reports only after
reparsing exact native cases and commands. Clean-source inventories, checked compiler/native
providers, host geometry, memory limits and cache policy must match; reviewed source differences
are explicit. Deterministic physical work must remain identical. Peak ratios are descriptive
candidate/baseline observations, not speedups or isolated-component estimates. Invalid comparisons
retire their stale output. Different fixture inventories require a new matching baseline.
