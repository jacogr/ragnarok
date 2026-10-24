# PVM preparation experiments

Opt-in experiments progress from arithmetic kernels to real guest loops, shared
program tables with memory/host effects, and the upstream sieve comparison below.
Production modules remain unchanged. Each stage has its own runner and recorded results.

## Initial arithmetic kernel

Initial scope: compare operand preparation for `add_imm_64` (149) and `xor_imm` (133), using
this checkout's actual JAM program validation, operand decoder and register evaluator.
Production modules remain unchanged. This is an opt-in arithmetic kernel, not an
alternative complete PVM engine or a reported production speedup.

Four engines run the same mixed-width signed-immediate bytecode and register inputs:

- `decode`: call the public decoder and production register evaluator every time.
- `cache16`: the original 16-entry direct-mapped PC-tagged decoder-cache model, then
  the same evaluator. Current production uses paired slots; this historical kernel
  model is not its current cache implementation.
- `prepared`: decode the entire sequence once; retain the same production evaluator.
- `compact-ir`: decode into scalar operation records and interpret two operations.
  This changes both representation and evaluator; its gain cannot be attributed solely
  to removing decoding. No instruction fusion or native emission is involved.

Sequences contain 4, 32 or 256 arithmetic operations, then an unexecuted validating
trap. Repetition is controlled by the benchmark harness, not guest control flow.
Each warm sample executes 1,048,576 arithmetic operations. The cache is fresh at each
sample's invocation boundary; prepared representations can be reused across samples.
Cold samples include per-invocation preparation, execution and destruction, excluding
the common validated-program construction. Increasing sequence sizes exposes cache
collisions, but does not establish a representative distribution of production programs.

Checks compare every register against an independent scalar oracle at 0, 1, 7 and 113
passes, for five sequence lengths and three seeds including `uint64.high`. Each timed
warm result is checked after stopping both clocks. Cold batches retain an output checksum.
Gas, memory, host calls, guest control flow, fault ordering and immutable publication
remain outside scope. Source-PC fields are retained but exit mapping is not implemented.

Run with the repository-pinned Nimony and Nim formatter. Existing provisioned tools
may be reused read-only; set their paths explicitly, rather than provisioning the full
client or modifying another checkout:

```sh
NIMONY=/absolute/path/to/pinned/nimony make -C experiments/pvm-ir bench
NIMPRETTY=/absolute/path/to/pinned/nimpretty make -C experiments/pvm-ir format-check
```

The driver verifies the compiler's `NIGHTLY.txt` commit against `spec/toolchain.json`.
It builds checked release ARC/Clang ThinLTO, runs two independent processes with three
warmups and ten rotated-order measured samples per case, then writes full evidence to
`build/pvm-ir-experiment/`: compiler diagnostics, raw samples, source/binary identities,
environment, preparation costs and a readable summary. No check-disabling flags apply.
Sub-few-percent differences are unproven; no deterministic instruction counters are
available on the initial macOS host. Preparation-only timing is a coarse observation.

Completion: pass the independent differential checks, run both measurement processes,
report warm and cold results including losses, and preserve the exact build identity.
The guest-loop follow-up below now checks the next execution boundary.

Initial wall-only timings were dominated by descheduling while other work ran. The
final probe retains both wall and process CPU time; summaries use the process CPU
clock (`CLOCK_PROCESS_CPUTIME_ID`) and retain wall samples for scrutiny. CPU time
still varies with CPU frequency and cache contention; these are local kernel results.
A deliberately failing assertion control must fail with its exact sentinel before
measurements are accepted. The only C helper reads the OS CPU clock.

See [RESULTS.md](RESULTS.md) for the recorded first measurement and interpretation.

## Real guest-loop follow-up

Run `NIMONY=/absolute/path/to/pinned/nimony make -C experiments/pvm-ir loop`.
This compares actual production `execute` with a generated experiment-only copy that
replaces its decoder cache with an immutable prepared table. It retains the production
register evaluator, gas simulation/cache, branch checks, budgets, exits and snapshot
publication bodies. A read-only cache parameter avoids copying the table on each call.
The generator requires the expected source anchors and saves an exact source diff.
Production source files and specification/toolchain pins remain unchanged.

The guest loop has 2, 16 or 64 add/xor body instructions, a counter increment, a real
conditional backedge and a dynamic halt. It runs for 1 or 10,000 iterations. Total guest
attempts are `(body + 2) * iterations + 1`. Three modes compare production execution,
reused preparation and preparation paid on every invocation. The fixed-loop oracle
models CPU/exit/charging behavior separately while using production pipeline prices.
Source ownership, byte-PC mapping, failure cases and memory tradeoffs are described in
[LOOP_RESULTS.md](LOOP_RESULTS.md), which records the final measurements and limitations.
Host and memory-fault semantics are not exercised by this increment.

## Bounded shared preparation, memory and host effects

The latest [memory/host results](EFFECT_RESULTS.md) show both the memory savings and
performance regressions of a program-owned representation. Run `make effects` or
`make effects-asan` in this directory with `NIMONY` set to the pinned compiler.
The second target runs a separate AddressSanitizer profile; its timings are discarded.

The new table has a private program owner, decoded records and a uint16 byte-PC index.
It is reused across fresh register/memory snapshots, fault repairs and valid host
memory replacement. Preparation returns typed refusals and enforces 4,096-code-byte /
256-instruction caps, giving a maximum 24 KiB payload (metadata and existing program
storage excluded). Exact maximum-size execution and owner lifetime are checked.
`shared_api.nim.inc` is appended to an experiment-only generated module, not installed
as a production API. Semantic execution bodies and ordinary build/test configuration
remain unchanged. Current coverage includes response-only host callbacks and 64-bit
scalar memory operations; other widths, fallible callbacks and Linux remain gates.

## Upstream sieve comparison

The [latest merged-master sieve results](SIEVE_MERGED_RESULTS.md#all-performance-merges-2026-10-24) refresh the earlier
[sieve results](SIEVE_RESULTS.md). They compare **PolkaVM interpreted**, a frozen master
interpreter and the prepared-table experiment on identical linked guest bytes. This
uses PolkaVM's actual `bench-prime-sieve` Rust implementation, rather than a hand-written
subset of PVM instructions. Its upstream README credits PrimeRust `solution_1`.
A project-owned export runs the sieve at a requested size, counts primes and checks
the count. Counting is additional work relative to upstream's stock `benchmark_run`;
these results cannot be compared directly with its published benchmark numbers.

With Python 3.12+, Rustup, Clang and the repository-pinned Nimony available:

```sh
NIMONY=/absolute/path/to/pinned/nimony \
POLKAVM_SOURCE=/absolute/path/to/pristine/pinned/polkavm \
make -C experiments/pvm-ir sieve
```

`POLKAVM_SOURCE` defaults to this checkout's `vendor/polkavm`; initialize that submodule
with the repository's setup workflow or reuse an existing pinned checkout read-only.
The driver verifies its commit, tracked cleanliness and recorded source hashes. It
provisions exact Rust toolchains: the upstream guest nightly with `rust-src`, and the
repository-pinned host Rust. Cargo resolves smaller isolated workspaces from upstream
lockfiles, refuses registry versions/checksums outside those lockfiles, and builds with
`--locked --offline`. All copied/generated sources, lockfiles and targets stay under
`build/pvm-ir-experiment/sieve/`. Existing tools and upstream sources are not patched.

Master defaults to commit `8ec989d66b378ef0d877bc73388794182912b97a`, frozen from
`origin/master` after the final PVM performance merges on October 24 (using the October 23 Nimony pin). The earlier result page
retains its original baseline and toolchain identities. Set `PVM_SIEVE_MASTER` to another local Git ref to
compare a different baseline explicitly. The driver archives its actual sources and
builds a separate baseline binary, checking that its Nimony pin matches the candidate.
`make sieve-build` and `make sieve-measure` expose the same two stages separately;
measurement refuses changed sources or binaries. Commands, diagnostics, assertion
controls, linked artifacts, opcode inventory, fixtures, raw samples and identities
remain in the ignored build directory. `results.json` is written only after all checks
pass; `partial.json` records completed groups if execution is interrupted.

The generated sieve variant raises only the earlier shared table's caps to 1 MiB of
code and 65,535 decoded records. The uint16 one-based index remains representable;
its maximum logical payload is just below 6 MiB. The earlier 4,096-byte / 256-record
experiment stays intact. An opaque benchmark binding captures program/CPU/memory
before timing, matching the other engines' invocation setup boundary. Execution uses
the existing semantic bodies; every opcode needed by this guest is available through
them. This is prepared interpretation, with no new native backend or specialized sieve
instructions.

## Complete prepared lifecycle and profiling

The [complete model and profiling report](FULL_RESULTS.md) covers all instruction
families, both pricing policies, scoped single stepping, both host callback forms,
resource admission, ownership, and repair/retry. It remains an opt-in generated module.
Run `make full` for correctness controls followed by the six-engine real-sieve comparison.
After that, `make full-profile PROFILE_ARGS=--sample` compares the original and borrowed
lookup against master with the same complete pricing and captures separate macOS CPU
profiles. Omit `PROFILE_ARGS` for timing without macOS sampling. Set `NIMONY` and
`POLKAVM_SOURCE` as above. Results include setup costs separately from reused execution.
