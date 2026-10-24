# Checked PVM instruction profiles

`make profile-pvm-guests` is an opt-in Linux x86-64 diagnostic. Manual CI
`suite=profile-pvm` selects a separate Ubuntu24.04 runner, installs the exact
Ubuntu Valgrind package `1:3.22.0-0ubuntu3`, and requires `valgrind-3.22.0`.
It never joins ordinary master/full/performance checks or persistent PR labels.
Compiler, protocol, upstream and guest pins remain unchanged.

The maintained source-snapshot guest driver is compiled with ARC, Clang ThinLTO,
release optimization and bounds/assertion contracts. C debug information adds
symbol attribution. A native assertion refusal must succeed before collection.
The pinned interpreted reference prepares the same independently state-checked
inputs as the paired comparison. Each profile executes one Pinky frame under
dynamic and complete-plan pricing, plus sieve100000 under complete-plan pricing.
All complete CPU/gas/page-state checks remain enabled.

Callgrind collection begins and ends at genuine `executeBudget_0_*` native
symbols. Missing symbols or zero instruction counts refuse the report; there is
no whole-process fallback. Input preparation, result validation and clock calls
remain outside collection. A compiled calibration driver contains selected and
excluded arithmetic: selecting the intended function must collect instructions
without the excluded function; selecting a nonexistent function must collect zero.
Generic process success, a crash or a partial raw profile cannot calibrate it.

Every raw call graph, Valgrind log and self-cost annotation is retained. `Ir`
counts executed native instructions. Conditional/indirect branch counts and
predictor misses are simulation diagnostics. Counts are neither CPU-cycle costs
nor timing predictions; all instrumented clocks are discarded for conclusions.
Paired uninstrumented CI remains the authority for speed claims. The profiler
uses one invocation, so it includes cold invocation-owned caches.

Source membership, frozen snapshot bytes, compiler command, executable, fixture
and preparation identities accompany successful evidence. Changed bytes, failed
full-state checks, invalid counters or annotation failures retain only partial
JSON and raw diagnostics after retiring old success. CI uploads diagnostic files,
never binaries, snapshots or compiler/dependency trees. Artifacts expire after30days.

This diagnostic changes no production semantics or representation. Documented M1
framing completion does not imply full state serialization or whole-block/JAM parity.
