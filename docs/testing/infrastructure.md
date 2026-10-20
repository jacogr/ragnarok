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
per-suite ARC evidence retirement and fresh observations remain mandatory. The parallel codec
pool uses a separate cache. A compiler-owned advisory lock serializes standalone and cumulative
unit invocations through evidence validation, including exceptional exits. Cumulative runs log
the active batch and its elapsed time.

CI partitions the discovered batch plan across eight bounded jobs, keeping each job's
linked/resource work sequential. Shards prepare only their selected native dependencies and
fixture providers, reusing sibling manifests from each provider once. Codec discovery belongs only to the first
partition and independent corpora only to the last; no tests or corpora are duplicated.
`UNIT_SHARD=index/count make check-unit` selects the same source-derived scope locally; plain `make check-unit` remains complete. Each shard
validates its exact expected identities and reports its scope, and a stable aggregate PR check
requires every shard to succeed. The 30-minute job limits and individual command timeouts remain
unchanged.

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
per-build caches. Progress logs identify the active build and elapsed time.

CI partitions the discovered ordinary contract families across two bounded jobs. Specialized
controls execute once, in the final partition. Each partition requires its exact predeclared
identities and diagnostic predicates; the stable contract check requires all partitions to pass.
`FAILURE_SHARD=index/count make check-failures` selects the same scope locally; plain
`make check-failures` remains complete. Ordinary partitions prepare only their declared native
providers. Job and individual command timeouts are unchanged, and summaries identify their scope.

Production and test adapters share `tools/build_crypto.py`, `tools/build_bandersnatch.py` and
`tools/build_quic.py`. `tools/native_dependencies.py` owns pristine submodule checks and logged
build commands. Production builds do not import test harnesses; independent equations, published
fixture checks, observation libraries and network scenarios remain in `tests/`. Dependency pins,
compiler flags, locked/offline Cargo builds and release adapter tests are unchanged.

Runtime failure suites keep ordinary case identities in `tools/failure_suites/<family>.json`, one case per
line. Suite defaults specify argument fields, labels and diagnostics; exceptional cases override
those values explicitly. The loader expands and validates expected identities and distinct log names before any probes run. Fixture-dependent probes, offload completion checks,
language-policy observations and store positive controls remain explicit in the runner.

Runtime, E2E and compiler-guard provenance use the same expansion, discovered by `tools/runtime_provenance.py`, using source-family extension
rules for `src/`, `native/`, `tools/`, `tests/`, `spec/` and CI workflows, plus all files in
`tests/fixtures/` and `vectors/`. The result is sorted and deduplicated before hashing. Build
outputs, Python caches, hidden artifacts and Cargo target directories are excluded. The Makefile
and existing required native fixture paths remain mandatory. Selected upstream documents/corpora
retain precise paths; runtime-owned pinned vector expansions remain unchanged. Missing local files,
escaping paths and incomplete evidence lists fail preflight; vendor provisioning remains separate.

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
verdict. `corpus_catalog.py` composes groups in the existing shared-build dependency order.
Registration runs no oracle or native process. Expected corpus identities exist before execution;
missing/duplicate verdicts and duplicate task/report keys are errors. All independent expected
values, trace coverage predicates, build refusals and exact output/hash comparisons remain in
the owning corpus task.

E2E orchestration uses `tools/e2e_plan.py`: ordered callable declarations supply both execution
and pre-execution completeness expectations. Setup tasks retain shared peer-build dependencies;
workload functions publish their returned verdict under their own name, and selftests retain
named suite rows. Missing, duplicate, substituted or failed selftests cannot satisfy the plan.
Direct offload selftests share the same callables, exact flags, marker checks and shutdown limits
with E2E; neither path maintains another list of their names. Registration performs no native or
network work. Failed builds never execute stale binaries, and failed offload selftests still
prevent the subsequent live offload workload.
