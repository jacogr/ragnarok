# Verification infrastructure

Native suite identities come from `tests/unit/<source-family>/test_<suite>.nim`, sorted by suite
name. Discovery rejects duplicate names, misplaced Nim files, empty trees and missing `.output`
contracts. `tools/verification_inventory.json` retains runtime misuse members, independent corpus
names and failure-family budgets. Independent names remain alphabetical within each JSON section;
missing sections, duplicate keys/cases and incomplete execution remain errors. The inventory loader
and JSON data are included in report provenance. Compiler guards do not import the runtime executor.

ARC requirements live in the owning unit source header, after its purpose/API documentation:

```nim
## Verification: {"arc": "example_arc_release"}
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
ordered libraries, headers, observer call-site renames, compiler defines and fresh-fixture
requirement.
Source-family directories match `tests/unit/`; suite filenames match the discovered test identity.
The loader discovers paths alphabetically, rejects duplicate suite identities, misplaced files,
unordered independent fields and unknown settings, and requires exact discovered-source coverage
and source-family ownership. Library/include/observer arrays preserve their explicit order; the
last library supplies the primary profile. Non-codec suites retain isolated execution, including
those without native libraries. Codec directory batches retain their dependency-free profile.
Metadata describes discovered suites; it does not select which source files execute.
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
case per line. The loader rejects duplicate keys, identities or log names, missing cases and empty
diagnostics against the separate coverage counts. Native linking, case order and subprocess
isolation remain unchanged. Wrapping behavior, positive controls, conditional variant diagnostics
and fixture-dependent case generation remain explicit in the runtime runner. Both the helper and
case data are included in report provenance.

Production and test adapters share `tools/build_crypto.py`, `tools/build_bandersnatch.py` and
`tools/build_quic.py`. `tools/native_dependencies.py` owns pristine submodule checks and logged
build commands. Production builds do not import test harnesses; independent equations, published
fixture checks, observation libraries and network scenarios remain in `tests/`. Dependency pins,
compiler flags, locked/offline Cargo builds and release adapter tests are unchanged.

Runtime failure suites keep ordinary case identities in `tools/failure_suites/<family>.json`, one case per
line. Suite defaults specify argument fields, labels and diagnostics; exceptional cases override
those values explicitly. The loader expands and validates the exact counts, distinct identities
and log names before running any probes. Fixture-dependent probes, offload completion checks,
language-policy observations and store positive controls remain explicit in the runner.

`tools/runtime_sources.json` lists literal runtime provenance inputs, alphabetically by
repository-relative
path, one path per line. The preflight rejects append-only or randomly prepended additions. Native
suite sources, fixture manifests, source globs and pinned vector expansions remain explicit Python
rules. Per-suite native requirement files and per-family failure files are discovered and hashed
automatically. The runtime hashes the inventory itself alongside every resolved input; a missing
input
still fails verification.

Run `make check-inventory` for a fast, Python-only preflight before opening a verification PR.
It validates per-family fields, build profiles, source paths, case counts, diagnostics and global
build/probe log uniqueness, then checks that every family file has exactly one explicit runner
call. It also checks native source/output coverage, compiler-rejection inputs and project-owned
provenance paths. It runs before setup in the normal verification targets. Every Linux CI job, including E2E,
also exposes it as a separate required step before its workload. A failed inventory check stops
that job before native setup. Vendor input bytes
remain the responsibility of the existing pinned-submodule setup and runtime provenance checks.

Add a failure family as `tools/failure_suites/<family>.json`, retaining one case per line, its
independent count in `verification_inventory.json` and an explicit `run_failure_suite` call at
the intended position. Alphabetical file loading does not change execution order. All family
files are automatically included in runtime provenance; no central list of JSON files is needed.

Provenance preflight checks all Python files recursively under `tools/` and `tests/`, plus
JSON files under `tools/`, against the exact source expansion used by runtime reports.
Add newly introduced helpers to `tools/runtime_sources.json`; existing explicit discovery
rules also count as coverage. Historical exceptions live in `runtime_provenance.EXCLUSIONS`
with a reason; missing, already-covered or unjustified exceptions fail preflight. This check
also catches untracked new helpers locally. Native sources and fixtures retain their separate
inventory checks; this policy does not claim complete dependency-graph discovery.

Corpus orchestration lives in `tools/corpus_codec.py`, `corpus_state.py`, `corpus_services.py`,
`corpus_crypto.py` and `corpus_network.py`. `test_runtime.run_unit` schedules their entry points
explicitly in the established order. State-root checks reuse the trie build, and width/namespace
checks reuse the composition build; failed builds must never run stale executables. Keep
independent expected-value generation in `tests/`, separate from these process/report adapters.

`tools/native_preparation.py` shares native library, integration reload and feature-fixture
assembly between the standalone Hastur entry point and cumulative runtime verification.
Feature adapters live in `native_fixtures.py`; callers own their output directories and report
serialization. Preparation failures propagate before any dependent suite is scheduled.
