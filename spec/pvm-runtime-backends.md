# Runtime PVM backend selection

## Scope and authority

`--pvm-backend ragnarok|polkavm-interpreted|polkavm-native` selects the actual guest
executor. The default remains the independent Ragnarök engine. Authorization, refinement,
accumulation and nested invocation dispatch retain ordinary Nim protocol hosts and state/effects
publication. This is implemented-scope client integration, not a complete validator.

Authority is Gray Paper `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d`, the existing PVM
execution/host/memory contracts, and pristine public PolkaVM API revision
`69e5b87c9888bc4f94cabdadc9661cf68a1bfbfa`. The maintainer authorized the optional
production adapter. No upstream source, toolchain, protocol price or independent interpreter
policy was changed. The bridge's locked transitive packages match the pinned upstream lockfile.

## Configuration and execution

Build the ordinary independent engine with `make`. Build the ordinary application with optional
PolkaVM support using `make PVM_POLKAVM=1`; `make build-pvm-runtime` builds the maintained
optional ABI alone. Missing support yields `BackendNotBuilt`; an unsupported requested engine
or unavailable sandbox yields `BackendUnavailable`. There is no fallback. Unknown or duplicate
selector values are rejected. Upstream environment selectors never override the explicit engine.
Startup logs effective engine and revision. The loaded bridge revision must match the source pin,
or execution refuses with `BackendRevisionMismatch`.

The PolkaVM adapters accept only owners captured by `decodeJamProgram`, the profile used
by standard application initialization and inner compilation. Raw-paper `decodeProgram` owners
have distinct jump-table interpretations and explicitly refuse with `BackendProgramUnsupported`;
they are never silently reinterpreted as JamV1. Ragnarök retains both existing decoding APIs.
The ABI's 128 MiB wire cap accommodates the bounded JAM code/table/bitmap envelope.

The selector is invocation-local. Authorization/refinement limits retain it, refinement replaces
any conflicting nested selection, and initial/later/current accumulation runner policies carry it
through ordinary CLI download, trace checking, fuzz target and development-node execution.
Numeric resource-policy files keep their existing schemas; the CLI selector is applied after
those policies are decoded. Independent dynamic/prepared/memo pricing APIs remain unchanged.

`StepOutcome.backend` records the actual completed engine; checked host terminal replies preserve
that receipt. Inner machine inspection exposes guarded `executed`/`backend` facts for its last
completed segment. A newly created machine has no execution receipt.

The narrow C ABI owns an opaque Rust instance/module graph. Its buffers are borrowed for one
call, and no Nim reference, callback, host behavior or protocol gas crosses into Rust. Normal
paths check explicit cleanup; a noncopyable private Nim owner also releases resources on unusual
exits. Rust unwinds are contained at every potentially failing C entry. ABI tests cover bad
buffers, contained unwind, full-width registers, reset memory/continuation isolation and layout.

## Gas, work limits and continuations

PolkaVM's public gas API is signed. This adapter disables its gas metering and keeps the complete
unsigned balance and canonical whole-block pipeline pricing in Nim. Affordability is checked
before subtraction. Paid-block state survives host suspension and repaired fault reentry; an
unpaid interior entry prices its complete containing block. The existing gas-analysis cycle limit
remains a distinct typed local refusal.

Public instruction tracing provides exact source-attempt boundaries, including OOG, fault and
host attempts. Instruction and callback budgets are separate from each other and from protocol
gas. Host callbacks run only after a genuine causing-PC suspension. The ordinary checked host
response function validates causing PC, code, full host identifier and posterior fields before
resumption. Callback failures remain their original typed host errors; engine/capability failures
publish no partial machine or state effects. Guest exits remain completed guest outcomes.

Native means the explicitly selected compiler, with actual machine code required. No interpreted
instance is accepted in its place. The interpreter's public arbitrary-entry path supports paid
and unpaid interior resumes. An engine unable to prime the exact requested instruction refuses
with `BackendReentryUnsupported`; it does not round the PC or run an unbounded prefix.

## Snapshot ownership and resident state

One private instance remains resident across synchronous host callbacks. Complete registers are
copied. Guest scalar store addresses mark at most two physical pages before aliased register
changes; deduplicated page tracking is bounded by the physical page domain. Publication reads
only potentially changed writable pages, compares complete images, and captures changed pages
with one immutable reference-vector merge. Unchanged page payloads remain shared. The next
callback transfers only changed immutable host pages and permissions into the resident instance.
No callback rebuilds the engine or all guest RAM.

Protected low-page bytes can remain in the Nim snapshot without being mapped upstream: both
implementations always trap guest accesses below 64 KiB. Inaccessible retained page bytes likewise
remain in Nim. Mapping, protection, removal and guest-store publication preserve complete owned
snapshots; no published memory borrows writable Rust storage. Separate invocations own separate
instances. The raw ABI also supports explicit reset for reuse/isolation verification.

## Capabilities and qualification

The optional crate builds on ARM macOS with the interpreted engine. Its pinned compiler gate is
x86-64; this manifest uses the Linux sandbox and does not enable the generic experimental
sandbox. Explicit native requests on ARM macOS refuse. Native qualification requires an actual
supported x86 Linux host with a working upstream sandbox, including `userfaultfd`.

The local x86 Linux image under QEMU correctly refused native construction. A direct pristine
public API probe reported `compiler_target=true`, `linux_sandbox_target=true`, then:

```
failed to initialize Linux sandbox: failed to create an userfaultfd: userfaultfd (errno = 38)
```

This is a local runner gate, not native execution evidence. The dedicated `runtime-pvm` CI
scope requires real compiled boundary/application/DOOM execution on Ubuntu x86; unavailable
native execution fails that qualification job. No native pass is claimed until that job succeeds.

This adapter deliberately uses upstream instruction tracing, documented upstream as a debugging
facility. It provides precise semantics and bounded attempts, not an optimized native-throughput
claim. Reusable compiled-module caching across independent application invocations remains future
work; residency currently spans one invocation and all its host callbacks.

## Verification and measurements

Maintained native suites:

- `make unit SUITE=pvm_runtime_backends`: independent default and missing optional support.
- `make unit SUITE=pvm_runtime_polkavm`: actual interpreted execution and, on supported Linux
  x86, required compiled execution. Covers unsigned gas, fault/repair/retry, paid/unpaid interior
  entry, cross-page fault ordering, protected bytes, complete registers, snapshot isolation,
  malformed/terminal/failed hosts, resident permission repair/removal, causing-PC validation, separate budgets and environment overrides.
- `make unit SUITE=pvm_runtime_application`: flag parsing reaches actual authorization,
  refinement, accumulation and nested execution; completed engine receipts bind the chosen path.
- Existing authorization/refinement/accumulation/inner/options suites retain their ordinary checks.

`make check-pvm-runtime-doom` uses the existing independently prepared pinned real guest and WAD.
It compares initialization and one actual tick, checking complete registers, gas, every page byte
and permission, all output events and source immutability through the production adapter.
ARM macOS interpreted runs passed both phases. Default/optional native suites, actual application
invocations and the Rust ABI checks also passed locally; the supported-host native gate remains
separate. Fresh debug semantic checking passed all production modules and the actual peer main.

`make bench-pvm-runtime` retains construction, initial mapping, cold preparation/execution,
resident reentry, reset and complete-memory publication separately in
`build/tests/pvm-runtime-measure/results.json`. This synthetic raw-ABI probe includes
Python/ctypes overhead and excludes Nim protocol pricing/dispatch; it is not application
throughput. Local interpreted samples completed and native was recorded unavailable. DOOM
correctness runs collect no local guest timings. CI retains each phase and real-guest verdict.

M1 foundation completion remains the previously documented implemented scope; it does not mean
complete state serialization, full JAM parity, native ARM compilation or a production validator.
