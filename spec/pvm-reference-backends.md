# Explicit PolkaVM reference backends

## Scope and pins

The optional reference executables now share one explicit engine constructor.
`RAGNAROK_PVM_REFERENCE_BACKEND=interpreter` is the default; `compiler` requests
PolkaVM's compiled backend. Other values fail. The selected engine must report the
requested backend and prints it in the retained log. Initialization failure is a
failure, never a fallback to the interpreter. Production Nim and corpus expectations
are unchanged.

Current PolkaVM is `acff91f0df4494b576471feb0c031066ab7406df`; the pinned Gray Paper
remains primary. The [stack-clamp qualification](pvm-polkavm-stack-clamp.md) records
the exact upgrade from the original `69e5b87c9888bc4f94cabdadc9661cf68a1bfbfa` evidence. Existing Rust and
transitive lock identities remain unchanged. The source manifest additionally records
the inspected backend/API/platform files at that same revision. Source evidence is
`src/lib.rs` (compiler target configuration), `config.rs` (`BackendKind::is_supported`),
`api.rs` (engine/module setup and CPU requirements) and `sandbox/linux.rs`
(dynamic-paging kernel setup).

## Capability and execution are separate observations

```sh
rustup run 1.99.0 cargo run --release --locked --offline --manifest-path tests/reference/polkavm_memory/Cargo.toml --target-dir build/polkavm-memory-reference-target -- --backend-info
RAGNAROK_PVM_REFERENCE_BACKEND=compiler make check-pvm-reference
```

The capability command reports compiler platform support, plain compiler-engine
initialization and dynamic-paging compiler-engine initialization separately. It prints
actual initialization failures to diagnostics and never enables kernel facilities or
experimental sandboxes. Engine construction alone is not proof that a module can
compile or execute; the requested full comparison run must still pass its probes.

At the pinned revision, compiler support is gated on AMD64 and the selected sandbox
platform/features. The maintained default Linux sandbox supports compiled execution;
non-Linux generic sandboxes require separate opt-in features/experimental permission,
which this change does not enable. Module setup also checks BMI2 for the compiler and
AVX2 for the Full cost model on AMD64. Dynamic paging requires Linux userfaultfd
permissions and the required kernel features (the pinned implementation diagnoses
kernel 6.8 or newer). These are source-derived prerequisites, not claims that every
Linux runner satisfies them.

The complete reference command includes dynamic-memory probes. A platform with a
working plain compiler but unavailable dynamic paging can therefore fail that run;
its failure must not be reported as complete compiled parity. No kernel setting or
host security configuration is changed by the runner or capability query.

## Reporting and test evidence

The runner validates the requested backend before launching a process, records it in
`results.json`, and hashes all project-owned Rust sources including the shared library.
The Actions summary shows that backend. Source declarations identify the gas simulator
and structural module-limit checker as backend neutral: those results do not claim
interpreter or compiler execution. Every actual engine-using checker selects the same
requested backend explicitly, while retaining its existing memory/metering profile.

Local capability observation on macOS/Apple Silicon is compiler platform false,
plain engine false and dynamic engine false. An explicitly requested compiler run
fails as unsupported; an unknown backend fails rather than choosing a default.
Standalone controls confirm neither request prints an interpreter execution result.
The full interpreter comparison and tooling controls are recorded after completion
below. No compiled execution result or remote Linux evidence is claimed locally.

This is correctness/capability preparation for the future consolidated performance
table. A backend unavailable for a benchmark workload must be marked unavailable with
its reason; it must not acquire an interpreter timing in the compiled column.

## Observed local completion

The rebuilt interpreter tools and all twelve paired native/reference groups pass
through the complete Make target after engine construction was centralized. Source,
lock, role/discovery and summary checks pass: 17 selected Python tests with one
pre-existing unrelated blocked Bandersnatch parity skip. Inventory and pinned Rust
formatting pass. Native source/configuration are unchanged from the preceding layer;
its checked formatting/runtime evidence is reused. The current Actions preview names
the interpreter and labels parser/simulator rows as backend neutral.
