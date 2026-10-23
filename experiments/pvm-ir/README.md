# Small PVM IR experiment

Scope: compare operand preparation for `add_imm_64` (149) and `xor_imm` (133), using
this checkout's actual JAM program validation, operand decoder and register evaluator.
Production modules remain unchanged. This is an opt-in arithmetic kernel, not an
alternative complete PVM engine or a reported production speedup.

Four engines run the same mixed-width signed-immediate bytecode and register inputs:

- `decode`: call the public decoder and production register evaluator every time.
- `cache16`: a 16-entry direct-mapped PC-tagged decoder cache, with the same lifetime
  and indexing strategy as the current execution cache, then the same evaluator.
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
Next possible increment: add one guest branch and prove exact gas/budget/PC behavior
before drawing conclusions about an IR execution engine.

Initial wall-only timings were dominated by descheduling while other work ran. The
final probe retains both wall and process CPU time; summaries use the process CPU
clock (`CLOCK_PROCESS_CPUTIME_ID`) and retain wall samples for scrutiny. CPU time
still varies with CPU frequency and cache contention; these are local kernel results.
A deliberately failing assertion control must fail with its exact sentinel before
measurements are accepted. The only C helper reads the OS CPU clock.

See [RESULTS.md](RESULTS.md) for the recorded first measurement and interpretation.
