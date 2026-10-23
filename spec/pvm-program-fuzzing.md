# Bounded program decoder fuzzing

This increment adds coverage-guided correctness testing of our PVM program decoder.
It exercises the existing Gray Paper and JAM deblob interpretations recorded in
[pvm-program.md](pvm-program.md), without changing protocol behavior or pins.
Guest execution and host functions remain separate future targets.

## Properties and input format

`tests/fuzz/pvm_program_target.nim` owns the native assertions shared by the native
unit suite, libFuzzer callback and standalone replay. Inputs are at most 1024 bytes.
The first byte is a test selector: bit 0 selects raw Paper/JAM decoding, bit 1 selects
an ordinary/zero program-byte limit, and bit 2 selects an ordinary/zero jump-count
limit. The remaining bytes are the complete program blob. The ordinary byte limit
is 1023 and the jump-count limit is 16; these are local test bounds.

Malformed inputs must produce a complete typed refusal. Successful inputs must
preserve instruction/opcode agreement, instruction addresses, containing block
membership, zero-suffix reads and typed out-of-range instruction/jump refusals.
Mutating the caller buffer after decoding must preserve captured code, instruction
operands and jump targets. Assertions remain fatal rather than becoming decoder
refusals. Frozen authored seeds cover raw/JAM forms, a literal, a branch loop and a
zero-width jump table. Their checksums live in the source-owned fixture descriptor.
The native suite also exercises truncations, every seed bit mutation and repeated
ARC ownership checks.

## Running and replaying

`make fuzz-pvm-program` provisions the pinned Nimony toolchain through the ordinary
Make dependency, then uses installed Clang and its no-main libFuzzer archive. It
runs a finite 100000-input campaign by default; `FUZZ_RUNS` accepts canonical counts
from 16 through 1000000. The driver fixes the maximum input length, per-input timeout,
RSS limit and random seed. Every invocation copies the frozen seeds into its own
mutable corpus under ignored `build/tests/pvm-program-fuzz/`.

Select an installed compiler with `FUZZ_CLANG`. If its resource directory has no
unique no-main archive, set `FUZZ_LIBFUZZER` to an installed static archive. For the
local macOS configuration used here:

```sh
FUZZ_LIBFUZZER=/opt/homebrew/opt/llvm/lib/clang/16/lib/darwin/libclang_rt.fuzzer_no_main_osx.a make fuzz-pvm-program
```

No dependency is downloaded or upgraded by the fuzz runner. The result records
compiler identity, runtime checksum, source hashes, build flags, seed checksums,
exact commands and logs. A successful campaign requires the exact requested run
count and actual coverage initialization/completion; stale or partial output fails.

Set `FUZZ_REPLAY=/absolute/path/to/case` on the same Make target to run the bounded
standalone reader instead of a campaign. It uses the identical native properties
without linking libFuzzer. Missing files and inputs larger than 1024 bytes fail.
Ordinary malformed decoder inputs are valid replay cases.

## Runtime and failure evidence

The profile retains checked release ARC/Clang with bounds checks and assertions,
adding address/undefined instrumentation and coverage; LTO is disabled for this
instrumented target. Normal generated Nimony startup initializes the runtime before
calling the public `LLVMFuzzerRunDriver` interface. The default Nimony allocator is
preserved. Sanitizer checks apply to intercepted C allocations, stack and globals;
individual native Nim heap-chunk boundaries and leak coverage are not claimed.

Pinned native Nimony assertions can exit directly without libFuzzer's exit handler.
A small POSIX C adapter therefore runs the driver in one joined child and snapshots
at most 1024 admitted bytes into a shared C record before entering the Nim callback.
On a failed child exit, the parent saves that exact case with exclusive creation.
No mutable ARC graph is shared between the processes. Python owns the invocation
process group and retires the whole group on timeout before reporting failure.
This adapter supports macOS and Linux; Windows support is pending.

Before a campaign, an assertion control must fail on a nonempty seed, emit its
assertion diagnostic, save a fresh case and pass independent replay through the
ordinary target. Timeout is never accepted as this control's expected failure.
The runner preserves incomplete/failure status and logs on every unsuccessful path.

Local evidence completed 100000 inputs with 414 coverage counters and 896 features,
plus frozen-seed replay and the assertion/artifact control. This is bounded decoder
correctness evidence, not complete interpreter or JAM parity. Next work includes
execution differential fuzzing, memory/host boundaries and continued measured
performance comparisons against pinned PolkaVM. Complete independent STF/JAM parity
remains open; documented M1 framing completion retains its existing scoped meaning.
