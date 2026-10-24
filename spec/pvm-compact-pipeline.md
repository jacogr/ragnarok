# Compact bounded pipeline records

Whole-block gas simulation keeps the same GP equations, approved wrapped-target pricing,
32-entry reorder buffer, issue/retirement ordering and cycle ceilings. Only private counter
representation changes. No public type, price cache, allocation policy or specification pin changes.

The exhaustive profile table grants latencies in 0..100. Remaining latency is copied from that
table and decremented only when positive. Resource demand is nonnegative; ALU/load/store totals
are at most four, multiply/divide at most one. Issue subtracts only after memberwise `fits` proves
every demand available. Completion returns exactly the previously held resources once, so every
availability counter stays within its initial bound. These fields fit signed bytes without
truncation, negative intermediate values or changed arithmetic. Cycle totals, frontend slots,
active counts, dependency masks and public gas remain at their original widths.

On the current 64-bit checked Nimony/Clang build, generated-C static assertions establish a
16-byte entry and 512-byte buffer, versus the preceding 64-byte entry and 2,048-byte buffer.
This deterministic 75% reduction is the main result. Two paired local corpus observations were
7.888→7.673 ms and 7.920→7.684 ms for complete pricing of the same 1,796 independent fixtures.
A separate confirmation was8.189→7.952 ms. The small CPU difference is not a general throughput guarantee. The maintained real-sieve run
measured 19.797 versus 5.891 ms at100,000 (Ragnarök versus interpreted PolkaVM); this is a fresh
local comparison, not evidence of a consistent sieve speedup over the preceding tree.

The gas suite replays every independent fixture and checks exact cycle ceilings. Five additional
original mixed-resource blocks repeat host/unlikely, load/store, multiply/divide, shift, conditional
arithmetic and move operations 1/4/32/33/65 times. Literal simultaneous-transition reference
(price,cycles) witnesses are (100,103), (276,279), (1956,1959), (2016,2019), (3936,3939), with one-cycle
short refusals. These cover maximum latency, resource contention and repeated full-buffer pressure.
Affected gas-domain/execution/host/retry suites, both maintained benchmark commands and Smoke
verify consumers. The prior 922-test Python result is reused: no Python source or dependency changed.

A producer-map algorithm regressed the independent corpus and was rejected. A waiting-stage
mask guard changed corpus timing by only0.6% and was rejected. Both experiments remain outside
production. The register-coordinate and compact-resource representations do not close the
remaining interpreter gap, full state serialization or whole-block/JAM parity. M1 framing remains
complete in its documented scope; fuzzing remains deferred pending Daybreak access.
