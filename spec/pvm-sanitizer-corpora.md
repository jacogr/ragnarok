# Calibrated AddressSanitizer qualification for PVM reference suites

## Opt-in profile and source authority

`make check-pvm-asan` provisions the maintained tools, then builds and runs the existing conditional
control, jump-table, scalar-memory, dependent-register-chain and scalar-register reference suites
under AddressSanitizer. Sources, fixture hashes, expected output and native assertions remain those
of the ordinary suite contracts. This analyzer job neither replaces their normal unit verdicts nor
launches Python discovery. It runs no fuzzing and changes no fixture, dependency or protocol pin.

The shared NativeChecks builder retains checked ARC/Clang ThinLTO and adds only
`-fsanitize=address`, `-fno-omit-frame-pointer` and C debug information, with the corresponding
sanitizer link flag. Builds/runs are sequential, with an isolated profile cache and report directory.
The pinned native allocator remains selected; no compiler/runtime source or allocator is patched.
Current selected suites require no libraries, generated inputs, custom defines or observer renames;
a changed unsupported profile refuses explicitly rather than silently omitting its requirements.

## Calibration and strict verdicts

The same pinned compiler/profile first builds a dedicated verification-only control executable.
A valid native-stack and C-heap read must succeed with its exact marker. A deliberate native-stack
overrun and a separate C-heap use-after-free must fail with their exact AddressSanitizer class,
one-byte read and intended raw-read symbol. A generic crash, unrelated failure, missing sanitizer,
wrong class or unexpected success cannot calibrate the analyzer. These intentional controls are
isolated from ordinary application/unit execution and retain their complete diagnostics.

Only after calibration may corpus replay proceed. Existing fixture contracts verify every required
byte before execution. Each binary must exit successfully, emit its complete golden output and
contain no sanitizer diagnostic. Native case assertions keep full CPU, gas, memory, permission,
source preservation and refusal checks; a partial output cannot become a passing result.

An earlier aggregate success is retired before setup/profile checks. A new aggregate is written
only after all controls and selected suites pass. The report retains exact build/run commands,
Clang version, compiler path/profile, binary hashes, source/output/fixture identities and logs.
The harness has focused positive, wrong-class/site, generic-crash, partial-output and stale-report
rejection tests.

## Observed completion and limits

Both calibration failures identify the intended instrumented read and the positive control passes.
All five reference suites pass their full unchanged assertions/output under this profile. Four
Python harness tests and pinned formatting pass. Reports/logs live under `build/tests/pvm-asan/`;
this increment's retained evidence is under `build/pvm11/sanitizer/`.

The observed run is macOS ARM64 with the pinned Nimony/Clang checked native profile; the tool also
targets maintained Linux Clang, but no Linux analyzer run is claimed here. ASan detects instrumented
stack/C-heap or region-boundary violations; it does not track logical suballocations inside the
native allocator's pools. This complements bounds checks, ARC lifetime assertions and independent
state oracles; it does not prove object-lifetime safety or substitute for future fuzzing.
M1 framing remains complete within its existing scope. Full state serialization and whole-JAM/STF
parity remain open; fuzzing remains paused pending maintainer Daybreak access.
