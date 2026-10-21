# Build and verification tools

[Project overview](../README.md) · [Development guide](../docs/development.md) ·
[Verification infrastructure](../docs/testing/infrastructure.md)

Python helpers here implement the Make targets for provisioning, building, formatting and
verification. Use the root [`Makefile`](../Makefile) as the command entry point so setup and
dependency ordering remain consistent.

| Tools | Purpose |
| --- | --- |
| `setup_*.py`, [`toolchain_archives.py`](toolchain_archives.py) | Provision pinned compilers, upstream sources and browser tooling |
| [`build.py`](build.py), `build_*.py` | Build the proof peer, native bridges, UI assets and embedded version metadata |
| [`format.py`](format.py) | Apply or check the pinned Nim and Rust formatters |
| [`check_inventory.py`](check_inventory.py), [`verification_inventory.py`](verification_inventory.py) | Discover and validate verification inputs |
| [`native_tests.py`](native_tests.py), `native_*.py` | Prepare fixtures/linking, run Hastur suites and collect native evidence |
| `test_*.py`, `corpus_*.py`, `e2e_*.py`, `failure_*.py` | Run verification groups, independent corpora, failure probes and peer scenarios |
| [`summarize_tests.py`](summarize_tests.py), [`runtime_provenance.py`](runtime_provenance.py) | Summarize reports and bind evidence to its inputs |
| [`compare_nimony.py`](compare_nimony.py) | Retain the bounded compiler performance comparison workflow |
| [`sync_stack.py`](sync_stack.py) | Reconcile legacy unregistered branch ancestry under the documented Git workflow |

[`native_requirements/`](native_requirements/) stores per-suite native requirements and
[`failure_suites/`](failure_suites/) stores runtime failure-family declarations.
[`browser/`](browser/) pins browser automation packages; the `ui_*.mjs` files drive browser checks.
The `telemetry_interop_*.py` helpers exercise the pinned JAM Tart collector.

Verification inputs and independent references live in [`tests/`](../tests/README.md).
Generated tools, caches, libraries, assets and evidence stay under ignored `build/`.
See [test registration](../docs/testing/adding-tests.md) before adding suites or probes, and
[the agent workflow](../docs/agent-workflow.md) before branch reconciliation.

The opt-in [NimScript POC](nimscript-poc/PORTING.md) compares
[`pvm_reference_summary.nims`](pvm_reference_summary.nims) with the retained Python renderer.
Run `make check-nimscript-poc`; it reuses Nim 2 from the pinned formatter archive and retains
its evidence under `build/nimscript-poc/`.
