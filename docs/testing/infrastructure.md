# Verification infrastructure

`tools/verification_inventory.json` owns the ordinary native suite identities, link profiles,
ARC evidence names, independent corpus names and compiler/runtime rejection inventories.
Each case or mapping occupies one line so concurrent additions produce small, reviewable diffs.
Keep independent names alphabetical within their inventory section; counts are coverage requirements
and
must match the runtime probes. `tools/verification_inventory.py` loads this data, rejects duplicate
object keys and cases, and preserves the consumers' tuple/list interfaces. Missing sections fail
at import; native discovery still checks checked-in suites and their expected-output files, and
verification still checks complete corpus/failure coverage. Both the loader and JSON data are
included in report provenance. Compiler guards do not import the runtime executor.

`tools/native_requirements/<source-family>/<suite>.json` declares one suite's source directory,
ordered libraries, headers, observer call-site renames, compiler defines and fresh-fixture
requirement.
Source-family directories match `tests/unit/`; suite filenames use the same feature prefix as the
execution inventory. The loader discovers paths alphabetically, rejects duplicate suite identities,
misplaced files, unordered independent fields and unknown settings, and requires exact inventory
coverage and the existing primary link profile. Library/include/observer arrays preserve their
explicit order. Discovery does not schedule suites: execution remains owned by the inventory.
`make check-inventory` loads these profiles before provisioning. New suites add their own file;
no shared manifest entry or central provenance-path addition is needed.
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
