# Verification infrastructure

Native suite identities come from `tests/unit/<source-family>/test_<suite>.nim`, sorted by suite
name. Discovery rejects duplicate names, misplaced Nim files, empty trees and missing `.output`
contracts. No central verification manifest is maintained. Runtime failure expectations come from
existing family declarations and source-owned specialized plans; corpus function registrations own
both scheduling and expected result keys. Duplicate identities and incomplete execution remain errors.
Compiler guards do not import the runtime executor.

ARC requirements live in the owning unit source header, after its purpose/API documentation.
Use a plain Nim comment so metadata stays out of generated documentation:

```nim
# @@Verification={"arc": "example_arc_release"}
```

The declared report key preserves historical report names. Suites without ARC observations need
no declaration. Duplicate, malformed, late and unknown declarations fail preflight. The launcher
still clears selected evidence before execution and requires fresh numeric observations with the
original cycle/schema counts and allocation-baseline checks; absence never counts as success.

Compiler-rejection fixtures are discovered under `tests/native/compile_fail/`. Each source owns
one required header declaration identifying its group and exact expected diagnostic. The validated
category views retain the existing privacy, nominal, contract, schema and ownership predicates.
Nominal declarations may include the ordered `early` call/positional diagnostic pair. Ownership
checks retain explicit lowering build names and the proof pool's enabled native profile. Missing
metadata and unsupported fields/profiles fail before setup; discovering a file never substitutes
a generic compiler error for its intended rejection. Fixture sources and their loader are hashed
in guard and runtime provenance.

Semantic rejection checks use fresh per-invocation worker caches. Each bounded worker checks a
contiguous lexical batch serially; concurrent workers never share a writable cache. A successful
`check` control initializes the frontend configuration before expected failures, allowing the
pinned compiler's normal import reuse. Without that control, a failing first build clears the
configuration memo and the next fixture rebuilds its import graph. The compiler owns dependency
invalidation; no compiler metadata is edited. Every fixture keeps its own process, exact diagnostic
predicate and retained log, and results retain declaration order. Failed controls fail the group;
temporary worker caches are discarded after the invocation.

Ownership guards retain real lowering builds and their original ABI/define profiles, using the
existing serial profile cache and compiler-owned lock. Different profiles remain isolated and
every main keeps its own output identity. Cache validation must cover imported and main-source edits
as well as private worker ownership; ownership failures still require the intended lowering
diagnostic rather than a semantic-only rejection.

`tools/native_requirements/<source-family>/<suite>.json` declares one suite's source directory,
ordered libraries, headers, observer call-site renames, compiler defines, fresh-fixture
requirement and optional static `fixtures` dependencies.
Source-family directories match `tests/unit/`; suite filenames match the discovered test identity.
The loader discovers paths alphabetically, rejects duplicate suite identities, misplaced files,
unordered independent fields and unknown settings, and requires exact discovered-source coverage
and source-family ownership. Library/include/observer arrays preserve their explicit order; the
last library supplies the primary profile. Non-codec suites retain isolated execution, including
those without native libraries. Codec directory batches retain their dependency-free profile.
Metadata describes discovered suites; it does not select which source files execute.

Static fixture contracts are discovered from `tests/fixtures/**/*.fixture.json` by
`tools/native_fixture_contracts.py`. The descriptor filename supplies its ID; the file declares
an environment variable, descriptor-relative target and explicit file-to-SHA-256 mapping.
Required bytes remain in provenance even if deleted. Duplicate IDs/keys, unknown dependencies,
invalid pins, escaping paths and conflicting per-suite environment assignments fail preflight.
The runner resolves each suite's own dependencies and checks every pinned member before use;
there is no central fixture-definition or consumer list. Generated-fixture providers retain
their existing preparation and fresh-input requirements.

Generated consumers declare a `provider` and optional `variant` in their existing requirements.
`tools/native_fixture_providers.py` registers callables at their definitions in
`tools/native_fixtures.py`. IDs derive from `unit_<id>_fixture`; raw functions return semantic
variant contracts rather than lists of consuming suites. Preflight rejects unknown providers,
unsupported variants and inconsistent `prepared` flags. Runtime binding derives the consumer map
from those validated requirements.

Provider metadata owns execution groups and unique numeric ranks, required certificate/CE inputs,
and top-level evidence keys/filenames. Derived plans preserve root and nested execution order;
the sealer aggregate retains its schedule fields and reverse-nested later evidence. Completed
root stages publish evidence immediately, with the historical validator write explicitly deferred.
The launcher derives generated-stage filenames from the same declarations. Native-library stages
retain their three established filenames. Missing manifests, duplicate consumers, bad variant
results and missing resources fail instead of reusing stale inputs.

Serial native suites reuse compiler intermediates only within the same source directory and
exact ordered compiler/linker profile. The cache identity also includes native library and header
contents and the compiler installation. Observer renames and feature defines therefore remain
isolated. Every main still compiles and runs in its own process; expected-output comparisons,
per-suite ARC evidence retirement and fresh observations remain mandatory. The codec batch uses
bounded private serial Hastur workers for unsharded runs: each worker keeps its own cache across a strided group
of discovered mains, with no concurrent cache sharing. Workers still run every main separately,
retain its expected-output verdict and report failure if any main fails. Cache identities include
the exact build profile; workers reuse only their own compatible intermediates. A compiler-owned
advisory lock serializes standalone and cumulative unit invocations through evidence validation, including exceptional exits. Cumulative runs log
the active batch and its elapsed time.

CI partitions discovered unit work across sixteen bounded jobs, keeping each job's
linked/resource work sequential.
Selected PVM AddressSanitizer replays are distinct `asan:<suite>` tasks in that same plan.
Their dependency weights are doubled to account for instrumented lowering and calibration;
ordinary suite identities and coverage remain separate. Each receiving worker calibrates its
private checked ARC/Clang ThinLTO profile once, then runs only its assigned instrumented tasks.
The unit verdict reconstructs the exact seeded selection and requires all positive/heap/stack
controls plus every selected replay. Corpus-only workers execute no sanitizer tasks.
`make check-pvm-asan` runs the complete instrumented selection locally through the same executor.
Partial sanitizer reports, logs and fresh ARC observations survive failures under
`build/tests/pvm-asan/`; the ordinary unit JSON embeds that profile's verdict and its Markdown
summary lists each control, planned replay, failure and artifact location. CI retains the JSON,
Markdown and diagnostics even when qualification fails.
 Each CI run derives batch weights from the number of unique
transitive project modules imported by its test sources, including test helpers. Static
`import`/`from`/`include` discovery includes all conditional branches and excludes standard-library,
generated and external sources; this is a cost estimate, never a coverage filter. The graph is
read once per invocation and needs no compiler setup, historical timings or maintained assignments.

Using `CI_SHARD_SEED=${{ github.run_id }}`, the planner randomizes ties, sorts batches by weight,
and forms blocks with one item per shard. Each block is independently dealt to random distinct
shards, including the final partial block, then each shard's execution order is shuffled. Codec
mains are independent single-suite items in multi-shard runs, with their existing checked flags,
private compatible caches, fixtures, expected outputs and fresh ARC observations. An unsharded
run keeps the reusable directory batch; CI never places the whole directory under one child deadline. The corpus
work runs once across four `Unit / Corpus (i/4)` matrix jobs alongside all sixteen suite-only shards.
Corpus dependency-connected bundles are shuffled with the same run seed and dealt round-robin;
there are no timing weights or maintained assignments. Each shard executes its assigned cases in
original feature/task order and reuses its own compatible driver builds. Consumers that read a
previous corpus result declare `requires` on their source-owned decorator and stay with that producer.
Native suite shards prepare only their selected native dependencies and fixture providers.
The Unit aggregate requires every native and corpus shard to succeed.
Corpus shard logs, caches and results live under `build/tests/corpus/<i>-of-4/`, separately from
native shard reports and the other corpus shard. Artifact retention includes each shard's logs/results.

Every runner uses the same seed, retained as `shard_seed` in results, logs and summaries. Rerunning
the same GitHub run preserves its assignment; a new run ID reshuffles it. Reproduce a partition
on the same source revision with `CI_SHARD_SEED=<run-id> UNIT_SHARD=3/16 UNIT_SCOPE=suites make check-unit` (or
`--shard-seed` on the underlying runner). Unseeded local partitions use a balanced lexical
stride; plain `make check-unit` remains complete and keeps its original execution order.
Use `make check-corpus` for the independent corpus scope only; neither scope can borrow the
other's verdict, and corpus-only runs reject a unit-shard selection. To reproduce a corpus partition,
use `CI_SHARD_SEED=<run-id> CORPUS_SHARD=1/3 make check-corpus`, followed by
`CORPUS_SHARD=1/3 make summary-corpus`. Omitting `CORPUS_SHARD` still runs the full corpus locally;
partial reports retain `corpus_shard` and `shard_seed` and cannot borrow sibling-shard results.
Exact expected identities are reconstructed from the recorded seed, and the aggregate check
requires every shard to succeed. CI jobs share a 60-minute limit; individual command timeouts remain unchanged.

`make check-inventory` loads these profiles before provisioning. New suites add their own file;
no shared manifest entry or central provenance-path addition is needed.

For `make unit SUITE=<name>`, the native launcher selects those requirements before preparing
libraries or generated fixtures. Only requested library-provider families run; shared production/
observer outputs still come from their existing provider. Static fixtures retain their checked-in
hash contracts. Prepared suites use their existing feature provider and keep only the selected
manifest, including every required byte source. QUIC transport prepares certificate inputs;
QUIC integration prepares CE/reload inputs independently. Missing selected providers or manifests
fail before execution. With no suite selected, aggregate provider order, nested fixture evidence
and full-suite execution remain unchanged. Make still provisions the pinned toolchain and sources.
Standalone preparation records both PVM gas and stepping evidence, including in full runs.

`tools/native_fixtures.py` separates schedule, markers, authentication, transition, commitment,
admission, disputes and availability preparation. Its aggregate entry point preserves the
historical preparation order and nested sealer evidence schema; each feature can also be
prepared independently. All new tooling and metadata are included in runtime provenance.

`tools/corpus_checks.py` compares complete native output against independently prepared expected
rows. The runtime runner retains corpus-specific generation, linking, provenance and additional
coverage predicates. The shared comparison preserves nonzero-exit rejection, missing/extra-row
rejection, exact output hashes, first-mismatch indices and build-failure refusal. It uses the
existing command runner's timeout and full logs. Specialized signature, proof and reused-driver
checks retain their explicit paths.
The shared `run_corpus` path writes exact request rows, builds the named driver with explicit
linking options, initializes request/hash evidence and calls the existing comparison. Callers
keep independent generation, corpus-specific metadata and coverage predicates. Expected hashes
previously retained after build failure remain opt-in so failed reports preserve their schema.

`tools/failure_drivers.py` discovers typed specialized probes from source-local
`failure_driver` headers and validates their `@@ProbeCases` enums. `tools/failure_controls.py`
registers handlers beside their ordered case plans, build profiles and exact failure predicates.
Expected identities, diagnostic budgets and handler scheduling derive from those declarations.
Preflight requires exact agreement between marked sources and registered driver handlers;
missing metadata, duplicate handlers/orders/identities and unsupported enums fail before setup.
Compiled `--list-cases` output must still match source declarations exactly. Store positive
controls, offload lifecycle and assertion/bounds/wrapping checks retain their own registered
handlers and original order. The runner delegates the specialized partition without a file list
or parallel dispatch sequence.

`tools/failure_checks.py` preserves the exact exit-code-1, expected-diagnostic and
`[AssertionDefect]` predicate for ordinary runtime guard probes, including complete command logs
and identity fields. `tools/failure_suites/<family>.json` lists fixed state-result builds and cases, one
case per line. The loader rejects duplicate keys, identities or log names, empty families and empty diagnostics.
Expected identities are expanded before execution and compared exactly with the observed rows. Native linking, case order and subprocess
isolation remain unchanged. Wrapping behavior, positive controls, conditional variant diagnostics
and fixture-dependent case generation remain explicit in the runtime runner. Both the helper and
case data are included in report provenance.

Contract verification opts into compiler-intermediate reuse only for matching source directories,
ordered compiler/linker profiles, native library/header contents and compiler installations.
Each driver retains its own executable and every probe remains a separate process. A group-owned
advisory lock protects shared build intermediates; other verification groups retain their existing
per-build caches. Independent unit corpora use this same profile-reuse path. Progress logs identify
the active build and elapsed time.

Units, independent corpora and runtime contracts keep ARC, Clang, release/speed optimization and
runtime checks enabled, but omit LTO to reduce compilation/linking cost. E2E, performance
workloads and the shipped peer use ThinLTO (`--passC:-flto=thin --passL:-flto=thin`), retaining
release/speed optimization and all runtime checks. The shared native builder defaults to
ThinLTO, including future production-like and fuzz callers unless they deliberately opt out.
LTO flags participate in the compiler cache identity, so incompatible intermediates cannot mix.

CI partitions discovered ordinary contract families and one specialized-control bundle across
six bounded jobs. The shared run-ID seed shuffles these work items before round-robin assignment;
controls keep their dependency order inside their randomly assigned bundle and execute once.
Each partition requires its exact predeclared identities and diagnostic predicates; the stable
contract check requires all partitions to pass. Reproduce a seeded scope on the same revision with
`CI_SHARD_SEED=<run-id> FAILURE_SHARD=2/6 make check-failures`. Unseeded local partitions retain their
historical assignment; plain `make check-failures` remains complete. Ordinary partitions prepare
only their declared native providers; the specialized owner retains full setup. CI jobs share a 60-minute limit; command
timeouts remain unchanged, and summaries identify the shard and seed.

Production and test adapters share `tools/build_crypto.py`, `tools/build_bandersnatch.py` and
`tools/build_quic.py`. `tools/native_dependencies.py` owns pristine submodule checks and logged
build commands. Production builds do not import test harnesses; independent equations, published
fixture checks, observation libraries and network scenarios remain in `tests/`. Dependency pins,
compiler flags, locked/offline Cargo builds and release adapter tests are unchanged.

`make check-python` provisions its sources with `setup_submodules.py --prefetch-blobs`, resolving the vector `git_blobs` paths already recorded in `spec/pins.json` against
the pinned tree and fetches missing objects together. This keeps network provisioning outside
Python discovery's deadline and avoids a separate lazy fetch per fixture. Warm/full clones
perform no fetch. Other groups retain focused setup. The sparse working tree, immutable pin and per-blob SHA-256 checks remain
unchanged; no second fixture registry is introduced. Python discovery runs references and
orchestration tests without compiling native binaries, so native LTO settings do not affect it.
The full discovery process has a 30-minute deadline, separate from the 60-minute CI job limit.
A timeout retains partial test progress and a fresh failed report; individual child-command limits
remain unchanged.

Runtime failure suites keep ordinary case identities in `tools/failure_suites/<family>.json`, one case per
line. Suite defaults specify argument fields, labels and diagnostics; exceptional cases override
those values explicitly. The loader expands and validates expected identities and distinct log names before any probes run. Fixture-dependent probes, offload completion checks,
language-policy observations and store positive controls remain explicit in the runner.

Runtime, E2E and compiler-guard provenance use the same expansion, discovered by `tools/runtime_provenance.py`, using source-family extension
rules for `src/`, `native/`, `tools/`, `tests/`, `spec/` and CI workflows, plus all files in
`tests/fixtures/` and `vectors/`. The result is sorted and deduplicated before hashing. Build
outputs, Python caches, hidden artifacts and Cargo target directories are excluded. The Makefile
and existing required native fixture paths remain mandatory. Selected upstream documents/corpora
come from `spec/crypto-pins.json` (Wycheproof member/license paths) and
`spec/quic-proof-pins.json` → `networking_source` (dependency path and document hashes).
JAM/Bandersnatch fixture membership comes from the existing
`spec/pins.json` → `vectors.files` and `spec/bandersnatch-pins.json` → `fixture_files` tables.
All declared entries join the shared expansion without additional runner filename lists or a
vendor-directory sweep. Duplicate JSON keys, conflicting pins, malformed tables and escaping paths fail
preflight. Missing local files and incomplete evidence lists also fail preflight; missing vendor
bytes remain listed and must be present when runtime, E2E or guard reports hash their inputs.
Vendor provisioning remains separate, and fixture-specific hash/revision checks retain ownership
of the expected bytes.

Run `make check-inventory` for a fast, Python-only preflight before opening a verification PR.
It validates per-family fields, build profiles, source paths, case counts, diagnostics and global
build/probe log uniqueness. Every validated family file is scheduled exactly once in lexical order. It also checks native source/output coverage, compiler-rejection inputs and project-owned
provenance paths. It runs before setup in the normal verification targets. Every Linux CI job, including E2E,
also exposes it as a separate required step before its workload. A failed inventory check stops
that job before native setup. Vendor input bytes
remain the responsibility of the existing pinned-submodule setup and runtime provenance checks.

Add a failure family as `tools/failure_suites/<family>.json`, retaining one case per line and
automatic scheduling from the validated directory. The declaration itself owns the
expected identity plan; no separate scheduler or count registration is needed. Ordinary families
are independent and execute in lexical order; each family retains its ordered cases and build options. All family
files are automatically included in runtime provenance; no central list of JSON files is needed.

Provenance preflight checks the discovered project input families against the exact expansion
used by runtime reports. New modules, helpers, source-local expectations and fixture files are
included automatically; no per-file provenance registration is needed. Historical exceptions live
in `runtime_provenance.EXCLUSIONS` with a reason; missing, already-covered or unjustified exceptions
fail preflight. Source and fixture discovery includes untracked inputs locally. Native suites and
compiler fixtures retain their separate semantic contract checks; hashing an input does not claim
that every code path was executed or that the expansion is a complete dependency graph.

Corpus orchestration lives in `tools/corpus_codec.py`, `corpus_state.py`, `corpus_services.py`,
`corpus_crypto.py` and `corpus_network.py`. `test_runtime.run_unit` schedules their entry points
explicitly in the established order. State-root checks reuse the trie build, and width/namespace
checks reuse the composition build; failed builds must never run stale executables. Keep
independent expected-value generation in `tests/`, separate from these process/report adapters.

`tools/native_preparation.py` shares native library, integration reload and feature-fixture
assembly between the standalone Hastur entry point and cumulative runtime verification.
Feature adapters live in `native_fixtures.py`; callers own their output directories and report
serialization. Preparation failures propagate before any dependent suite is scheduled.

Specialized runtime drivers declare their command names once in a `VerificationProbe` enum tagged
with `# @@ProbeCases`. Python reads this strict declaration before execution; the compiled driver
also exposes `--list-cases` before fixture preparation, and the harness checks both enumerations
agree. Dispatch uses the enum values without a catch-all branch, so Nimony checks exhaustiveness.
`failure_plans.py` expands default/error/absence and enabled/disabled variants while preserving
specialized diagnostics, positive controls and language-policy observations. Verdicts reject
missing, duplicate, replaced and failed cases, even when a replacement preserves the row count.

Each independent corpus is a named callable registered in its owning module's `CorpusGroup`.
The function name supplies its single report identity; the scheduler publishes its returned
verdict. `corpus_catalog.py` discovers `corpus_*.py` modules and their `CorpusGroup` instances.
Each group owns a unique numeric `order` preserving shared-build dependencies, plus ordered
`resources` names when it needs generated fixtures. Discovery rejects empty groups, duplicate
orders/task names and unknown/repeated resources before execution; adding a feature needs no
central import or scheduling-list entry.
Corpus runners share request serialization and exact comparison through `corpus_checks.run_corpus`.
Additional positional fixture inputs precede the request file; callers retain their historical
request-evidence fields, build options and complete-output predicates. Uniform guest scenarios
share `corpus_state.guest_scenario`, while specialized materialization and coverage checks remain
explicit in their owning tasks. `native_fixture_contracts.validate_fixture_contracts` checks every
selected pinned member afresh at the owning task's validation boundary; successful checks are
not memoized. Fixture identities, independent equations and source-owned registrations remain
with each case.

Registration runs no oracle or native process. Expected corpus identities exist before execution;
missing/duplicate verdicts and duplicate task/report keys are errors. All independent expected
values, trace coverage predicates, build refusals and exact output/hash comparisons remain in
the owning corpus task.

Scenario test setup shares mechanical indexing through `tests/scenario_states.py`, preserving
caller-owned snapshots, actual successor slots and each suite's initial-slot policy. Replay
adapters share restart/trace framing through `tests/scenario_replay_oracle.py`; the owning
modules retain their frozen fixture/source pins and native defines. These helpers derive no
protocol outcomes and do not replace feature assertions or independent scenario equations.

The independent Python Thin-signing reference memoizes deterministic public-fixture signatures in
an invocation-local LRU cache of at most 4,096 entries. Keys include the scalar, input bytes and
additional-data bytes; results are immutable proof/output bytes computed by the same independent
mathematical equations. Scalar validation still runs before lookup, mutable buffers bypass the
cache, and native observations never supply expected values. Expected-output comparisons and all
corpus cases remain unchanged; this cache only avoids repeating identical reference calculations.

E2E orchestration uses `tools/e2e_plan.py`: ordered callable declarations supply both execution
and pre-execution completeness expectations. Setup tasks retain shared peer-build dependencies;
workload functions publish their returned verdict under their own name, and selftests retain
named suite rows. Missing, duplicate, substituted or failed selftests cannot satisfy the plan.
Direct offload selftests share the same callables, exact flags, marker checks and shutdown limits
with E2E; neither path maintains another list of their names. Registration performs no native or
network work. Failed builds never execute stale binaries, and failed offload selftests still
prevent the subsequent live offload workload.

Persistent native/Hastur caches rely on the pinned compiler's source dependency invalidation.
The October 21 nightly fixes the reproduced stale imported-generic call; the former whole-tree
[source epoch](../../spec/pvm-native-cache-identity.md) and digest memoization are retired.
Source edits reuse the same profile cache so the compiler's invalidation is exercised. Compiler
identity, checked flags, native library/header hashes, worker isolation, locks and independent
source provenance remain in force. Compiler files and metadata are never modified.

Storage IO observers are explicit native-only profiles: the `storage_io` test object and include
directory are required for `io_read`, `io_write` or `io_fsync` call-site observation. SDK prototypes
are included before redirection to preserve platform aliases. Ordinary and production compilation
receive no redirection header or fault controls. Every unrefused call uses real OS IO.

Ubuntu prerequisite setup stays in `make host-tools`. Missing packages trigger APT acquisition
with three retries and 30-second HTTP/HTTPS connection/data timeouts; package-lock waits are
bounded to 60 seconds. Index updates additionally have a five-minute wall-clock limit with a
ten-second termination grace, and any failed index makes setup fail. Installation begins only
after a successful update; package configuration retains its normal completion semantics.
Both stages save stdout/stderr in `build/ci/host-tools-{update,install}.log`, covered by the existing
CI artifact globs even when compiler setup never starts. Provisioned and non-APT hosts skip this
path. The workflow uses one shared 60-minute limit for every job.

E2E builds opt into the same serial, source-epoch/native-ABI/profile-isolated compiler cache,
retaining ThinLTO, runtime checks and separate production feature defines. Current-sequence,
preimage, guarantee and rotation workloads share one freshly compiled responder; each still
launches independent processes and state, checks fixture hashes and publishes its own required
verdict. A failed shared build blocks every dependent workload from running stale binaries.
The E2E report records setup, workload and selftest durations under `task_timings`, including
tasks which raise, so build costs can be distinguished from live scenarios.

JAM fuzz interface corpora register in `tools/jam_fuzz_corpora.py`, outside Unit corpus discovery.
`tools/jam_fuzz_checks.py` owns their socket and upstream minifuzz checks; these are not E2E
workloads. `Fuzz / JAM` runs the complete interface plan once with its own setup, failure gate and
artifacts. Complete local `make check` includes that same target once. This is fixed-reference
interface coverage; it does not claim a generated fuzz campaign.
The JAM matrix runs three partitions: two seeded random native-corpus partitions and one complete
socket/minifuzz partition. There are no timing weights or maintained case assignments. The Fuzz
aggregate requires all three, alongside PVM fuzz. Each owns private logs, caches, results and summary
under `build/tests/jam-fuzzer-interface/<i>-of-3/`; its report records the selector and seed, and its
verdict reconstructs the exact expected inventory. Corpora and integration evidence cannot satisfy
one another's scope. Reproduce with `CI_SHARD_SEED=<run-id> JAM_FUZZ_SHARD=1/3 make check-jam-fuzzer-interface`;
use `3/3` for socket/minifuzz. Omit the selector to run the complete local plan.


CI runs E2E families in parallel on separate VMs: Testnet (RPC, state, explicit downloads
and full Tiny testnet acceptance), Current Downloads, Telemetry and Transport (peer entry
points, retained/integrated services,
mesh, resilience, soak and offload). Decorators beside each verdict declare its group and
earlier prerequisites. Selection closes over those prerequisites in original declaration order;
only setup builds may be shared between groups. Every workload and selftest has exactly one
owning group. Network/resource scenarios remain sequential inside each VM, with independent
native dependencies, fresh fixtures, reports and uniquely named evidence artifacts.
`E2E_GROUP=<group> make check-e2e` runs one complete family; plain `make check-e2e` retains the
complete serial plan. Reports and summaries explicitly identify partial group scope and require
all that group's declared verdicts. The stable **E2E** aggregate requires every
matrix job to succeed, including refusal of skipped/cancelled groups. All jobs use the shared 60-minute timeout.

The automatic PR **Smoke** gate runs `make check-smoke`: complete read-only pinned Nim/Rust
formatting, real UI asset generation and an unoptimized (`--opt:none`, no release/LTO) semantic
compilation of every discovered `src/**/*.nim` module. A generated import-only module visits all
sources, including modules not currently reachable from the peer. Unique import aliases avoid
namespace collisions. The real peer entry point is also checked with integration/offload and
main-module semantics. Both compiler operations must pass; reports show the complete inventory
and shared compilation verdict, not independently measured per-module results.

`check-modules` uses this same complete-graph scheduling with its checked-release profile.
Neither path repeats the import graph in hundreds of separate fresh compiler processes. Each
invocation uses fresh private compiler caches; the two operations retain their distinct cache
profiles. No fixture submodules, Cargo dependency builds, native bridges or link step are needed.
Compiler/formatter setup is separate from native C/linker package provisioning; UI bootstrap
provisions a C compiler only if the host lacks one. New PR updates supersede only older smoke
runs, leaving labeled heavy CI alone. Formatting checks exactly the same whole source set as
full CI and never edits source files.


## Native PVM comparison runners

`Perf / PVM Comparison` runs independently on native Linux x86-64 (`ubuntu-26.04`) and
Linux ARM64 (`ubuntu-26.04-arm`). It retains the existing master, explicit Perf/Full and
manual comparison triggers; ordinary PR updates still run the lightweight Smoke check.
The Unit matrix is unchanged.

Each comparison first runs `make check-pvm-native`: the maintained executable-storage,
whole-state, opcode, host/region and exclusive-owner gates. ARM64 requires actual native
publication and execution, plus forced-refusal controls. Linux x86-64 qualifies the checked
interpreter and unavailable ARM64 fallback; it does not claim an x86 JIT. Process uname,
declared Actions architecture and the existing pinned Nimony archive must agree before
qualification. Failure leaves incomplete evidence and fails the job.

Linux x86-64 uses `make bench-pvm-interpreter`; ARM64 uses the maintained
`make bench-pvm-arm64-applications` cohort. Both retain pinned PolkaVM inputs, complete-state
checks, both process orders and distinct constructor/cold/reused records. The ARM64 cohort
includes public JIT-on/off calls, retained-core diagnostics, Pinky, sieve (100k/10m),
minimal, fill and DOOM initialization/gameplay. Its DOOM reference evidence separates raw
calls from restore/call/teardown lifecycle costs. Optional x86 prepared-baseline input
continues to apply only to that driver; the ARM64 driver defaults to the current head as
its same-source control. No cross-architecture or cross-CPU timing ratio is calculated.

Architecture-specific artifacts retain source/compiler/input identities, native counters,
logs and summaries on failure as well as success. Native timing results are evidence for
that runner only; existing Docker ARM64 correctness receipts are not native timing results.
