# Upstream fuzz campaigns and the JAM execution bridge

`make fuzz-pvm-upstream` runs the original PolkaVM fuzz targets and separately
compares JAM-adapted generated programs with Ragnarök. It changes no production
PVM code and is independent of the prepared-execution experiment and pvm #8.
The reference commit remains `69e5b87c9888bc4f94cabdadc9661cf68a1bfbfa`.

## Original campaigns

The runner cross-checks the pinned Cargo manifest against upstream's CI target
inventory. Each original target source, manifest, lockfile and nightly descriptor
has a SHA-256 expectation in `spec/polkavm-pins.json`; a dirty reference checkout,
missing target or changed pin fails before execution. Only dependency paths in an
ignored manifest are relocated to the pristine vendored crates. Target bodies,
`Arbitrary` implementations and dependency versions remain unchanged.

| Original target | Property owner | Platform |
| --- | --- | --- |
| fuzz_extended_decode | Extended instruction decode determinism | Linux, macOS |
| fuzz_generic_allocator | Generic allocator operation sequences | Linux, macOS |
| fuzz_linker | Linker input handling | Linux, macOS |
| fuzz_page_set | Page-set operations against a naive bitmap | Linux x86_64 |
| fuzz_polkavm | VM interpreter execution/cache configurations | Linux, macOS |
| fuzz_program_blob | Blob memory-usage estimation | Linux, macOS |
| fuzz_shm_allocator | Shared-memory allocator operation sequences | Linux x86_64 |

The original VM target retains its `Latest64` profile and randomized interpreter
cache settings. `CORRECTNESS_FUZZER` is removed from the subprocess environment,
so these runs do not select upstream's compiler comparison mode. Running these
Rust targets alone provides no evidence about Ragnarök's interpreter.

Make installs the exact upstream `nightly-2025-03-29` separately from our host
Rust and Nimony toolchains. Cargo uses `--locked`. The build applies libFuzzer
coverage instrumentation directly, following the [cargo-fuzz build flags](https://github.com/rust-fuzz/cargo-fuzz/blob/main/src/project.rs),
so no separately versioned cargo-fuzz CLI is needed. Linux uses AddressSanitizer;
checks remain enabled. Leak detection is disabled, so this is not a leak check.
On macOS 27 the pinned ASan runtime deadlocks in dyld initialization before main;
local macOS runs therefore use coverage without ASan and report that explicitly.
The two Linux-only targets are reported as unsupported locally. CI requires the
complete Linux x86_64 inventory and ASan, and cannot accept a partial-platform run.

A campaign must exit successfully, load counters and PC tables, report nonzero
coverage/features, and finish the exact requested count. A timeout, sanitizer
failure or target that never reaches its properties fails the run. VM seeds are
bounded deterministic raw inputs. Blob-estimation seeds contain all required
`Arbitrary` fields; short empty-corpus campaigns otherwise never reach this target.
These are project-supplied seeds, not a claimed upstream saved corpus.

## JAM bridge boundary

The generated reference executable includes the unchanged upstream VM generator
slice, from `CacheSizeConfig` through `transform_code`, and appends the maintained
public-API adapter in `tests/fuzz/pvm_upstream_bridge.rs.inc`. It decodes the exact
upstream `(Vec<OperationKind>, Option<CacheSizeConfig>)` input type. It consumes
both deterministic seeds and the actual corpus retained by the original VM
campaign; reports preserve their separate provenance and require mutated inputs
to reach the bridge.

Adaptations are explicit:

- Serialize the same generated instruction operands as `JamV1`, after checking
  every opcode's JAM membership. Reject an entire program with a non-JAM opcode;
  never substitute a trap for an unsupported instruction.
- Append a physical terminal trap. JamV1 admission requires a final terminator,
  including after a final conditional or fallthrough (see GP-PVM-004).
- Use the interpreter with `Sync/Full/L2Hit` pricing, 512 gas and dynamic paging.
  The reference's default pricing is unrelated to JAM; the adapter selects it
  explicitly. Upstream randomized cache limits are recorded as implementation
  policy and are not applied to this semantic comparison.
- Run two register profiles: zeroed registers with RA set to `RETURN_TO_HOST`,
  and documented mapped-address/arithmetic boundary values. Map two writable
  pages at `0x10000` and `0x11000`, initialized with `(offset * 17 + 3) mod 256`.
- Bound raw inputs to 4096 bytes, decoded operations to 256 and serialized JAM
  wire bytes to 8192. Arbitrary refusal, operation limits and non-JAM opcodes
  have separate counts. No semantic mismatch is classified as an unsupported case.

The native property module calls the production `decodeJamProgram` and `execute`
APIs with assertions and bounds checks retained. It compares exit, all thirteen
registers, unsigned gas, PC, fault page, every mapped byte and retained writable
permissions. Panic/Halt PC is normalized to zero under our existing terminal
snapshot contract; the raw reference PC remains in the frame. Source registers,
PC, gas, page permissions and bytes must remain unchanged after execution.
The native 100,000-step/cycle ceilings are local failures, never guest exits.
The comparison does not infer a public reference equivalent for `blockCharged`,
and does not claim host-call, arbitrary permission-map or full ISA coverage.
Serialized opcode diversity is reported separately from executed coverage.

Frozen raw inputs and both reference frames for fault, halt, gas exhaustion,
mapped store and register/trap cases live under `tests/fixtures/pvm-upstream-fuzz`.
The source-owned fixture descriptor pins their bytes. `make unit SUITE=pvm_upstream_fuzz`
replays these observations through the same native property module, without Rust,
libFuzzer or network. Truncation and invalid-format controls fail admission.
The opt-in campaign also corrupts an expected register and requires the exact
native assertion failure, proving checks remain active in the replay binary.

## Run and reproduce

```sh
FUZZ_RUNS=10000 make fuzz-pvm-upstream
make unit SUITE=pvm_upstream_fuzz
```

`FUZZ_RUNS` accepts 1000–1000000 runs per original target. Make's shared fuzz
default is 100000; CI sets 10000. Each campaign has a 600-second libFuzzer wall
budget plus a 660-second process-group timeout, 20 seconds per input, 4096-byte
inputs and a 4096 MiB RSS ceiling. Hitting time/RSS limits does not pass a shorter
campaign. The mutable corpus persists between local runs; choose a run count
larger than its initialization size. Commands, tools, source hashes, coverage,
input provenance, skip accounting and frame hashes are retained in
`build/pvm-upstream-fuzz/results.json`, with a Markdown summary and separate logs.
No speed comparison is inferred from fuzz timings.

For a bridge mismatch, artifacts retain the exact original raw input and complete
reference frame, including profile suffix. After the initial build:

```sh
build/pvm-upstream-fuzz/replay build/pvm-upstream-fuzz/artifacts/bridge/INPUT-0.bin
python3 tools/fuzz_pvm_upstream.py --replay-raw build/pvm-upstream-fuzz/artifacts/bridge/INPUT.raw
python3 tools/fuzz_pvm_upstream.py --replay-raw build/pvm-upstream-fuzz/artifacts/bridge/INPUT.raw --minimize
```

The bounded reducer tries at most 64 deletion candidates and retains the same
profile and semantic assertion. It writes retained raw bytes, reference frame and
signature under `build/pvm-upstream-fuzz/reproduction/`; it does not promise a
mathematically minimal input. Reference/build failures and local timeouts stop
reduction rather than masquerading as a semantic mismatch. Copy a confirmed
minimized regression into the ordinary frozen fixture suite; production fixes
belong in their own PVM work.

Original libFuzzer failures save their own inputs under
`build/pvm-upstream-fuzz/artifacts/TARGET/`. Replay with the recorded original
binary/flags and input path; upstream libFuzzer's `-minimize_crash=1` mode can
reduce those original-target crashes. Neither path modifies the vendored source.

The independent **Fuzz PVM** CI job runs on master, full verification requests,
and `workflow_dispatch` with `suite=fuzz-pvm`. It retains logs, partial/final
results, summary and failing original inputs/reference frames even after failure.
It is separate from PVM reference and performance jobs and ordinary native tests.
