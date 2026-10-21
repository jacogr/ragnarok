# Invocation-local price reuse across host continuations

## Scope and invariant

The [segment-local optimization](pvm-interpreter-block-cache.md) leaves host-heavy
workloads unchanged. The follow-up sample still ranks `blockGas` first (259 top-of-stack
samples), and those workloads repeatedly resume the same program after callbacks.

Extend the same constant-space successful-price memo to one `executeWithHost` call,
for both callback forms. `HostResponse` can change registers, gas and immutable memory;
it cannot replace program bytes, the decode profile or the caller's fixed cycle limit.
`applyHostResponse` retains the suspended machine's program owner. These existing
contracts bind cached prices across continuations without adding a public API or
caching balances, callbacks, contexts or failed simulations. Independent/nested calls
still have their own stack-local memo, discarded on any return.

Pinned GP 0.8.0 pricing and documented PolkaVM exceptions are unchanged. Preserve
instruction/dispatch limits, paid-block flags, exact gas debits, host refusal ordering
and caller source snapshots. Check repeated metered host loops with both callback
forms, lower simulation limits on subsequent calls and host/step budget refusal.
Retain existing host-response/failure and metered repair corpus checks. Compare matched
baseline/final binaries on the same validated fixed workloads before accepting gains;
compiled comparisons remain deferred and all build/runtime checks stay enabled.

## Observed local completion

Both callback forms pass a real 17-visit metered loop with exact remaining gas and
all thirteen final registers. Nested callback execution uses a different program at
the same PC without contaminating either call's price; lower cycle limits on later
invocations refuse before callbacks. Dispatch/step shortages preserve the exact
prior callback count, and retained source snapshots remain unchanged. The selected
host execution/failure/response and guest execution suites pass with stable 1000-cycle
ARC observations. All fourteen independent reference/native groups and the unchanged
interpreted benchmark pass. No compiled backend was requested.

Matched checked ARC/Clang LTO executables on Apple M1 Max used the same fixture,
three process warmups and ten paired opposite-order runs, retaining 100 measured
samples per workload/version plus validated driver warmups. Medians in microseconds:

| Workload | Segment-local memo | Invocation-local memo | Before / after |
| --- | ---: | ---: | ---: |
| arithmetic-10000 | 2496.17 | 2494.67 | 1.00× |
| memory-aligned-1000 | 609.19 | 606.92 | 1.00× |
| memory-crossing-1000 | 768.17 | 764.63 | 1.00× |
| hosts-aligned-1000 | 2137.27 | 842.17 | 2.54× |
| hosts-crossing-1000 | 2306.52 | 1002.62 | 2.30× |

Only the host-heavy 2.54×/2.30× changes are claimed as improvements; guest-only
differences are within noise. Raw samples, ranges and source/binary hashes are in
`build/pvm-host-price-profile/ab-results.json`. Local observations do not establish
an exact-head Linux result.

## Incremental-build observation

Changing the private `nextHost` signature exposed stale generated C calls in an
unchanged generic consumer and the existing benchmark cache. Clang reported four
arguments against the new five-argument declaration. Original failing caches/logs
are preserved under ignored `build/pvm-host-price-stale-cache` and
`build/pvm-host-price-benchmark-stale-cache`. Rebuilding the identical source into
fresh project-owned caches passes; no compiler source/metadata or checks were edited.
This is a reproduced incremental-cache limitation of the pinned Nimony setup, not
a reason to accept a failed build or relax guest correctness. A source-sensitive
project cache boundary needs separate tooling review; no compiler-wide diagnosis or
minimal standalone reproducer is claimed by this runtime optimization.
