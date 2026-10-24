# Borrowed owners for reusable price lookups

## Scope and lifetime proof

Exact-start complete-plan and lazy-memo queries now borrow their backing owner for the duration of
the synchronous lookup. The caller retains the supplied handle throughout the call. Complete-plan
queries only read immutable table storage. Memo queries may populate successful prices, but their
simulator invokes no caller code, changes no owner handle and cannot replace the memo's identity.
The documented exclusive-use requirement for mutable memos remains. No borrow escapes or enters
a result; returned block prices are copied scalar values.

Nil-owner, full-width address and exact-start checks remain before access. Failed simulations
retain no partial price or occupancy increment. Program identity, cycle ceilings, byte ceilings,
preparation behavior, guest gas and callback validation are unchanged. All specification, fixture
and toolchain pins remain fixed. This changes neither prepared IR nor any public field/API.

## Measurement and qualification

Generated C confirms that each successful public lookup formerly retained its local owner and
released it on return. Complete-plan code has three release sites (one selected per invocation),
while memo code has one. Borrowing removes that retain/release pair and its cold destructor
branches. The generated lookup bodies shrink from10359 to1735 bytes of C for complete plans and
3480 to517 for memos; those source-byte counts are compiler evidence, not machine-code size.

`make bench-pvm-pricing` now measures public exact-start queries using three independently framed
trap blocks with literal two-gas prices, plus an invalid one-past-code start. Each policy emits
thirteen samples of two million queries, checking the complete checksum and unchanged/bounded
memo occupancy. The report retains every row, including the cold memo sample, and separately
summarizes the last ten. Parser controls reject missing, extra, reordered, malformed, nonpositive
timing and wrong-checksum rows before publishing a report. Setup and checked native build flags
come from the maintained Make/toolchain path. This isolates lookup cost; it is not an interpreter
throughput benchmark.

Two reversed-order before/after runs of that isolated probe measured warm medians of6.660/1.329 ms
for complete plans and14.889/7.469 ms for memos (before/after). The public lookup workload is about
80%/50% faster locally, including the compiler's resulting optimization opportunities.

Two paired maintained-guest comparisons each pass936 complete-state invocations at both workload
sizes under dynamic, complete-plan and lazy-memo pricing. The repeat comparison is mostly within
1.5% in either direction; no whole-interpreter speedup is claimed. Another1716 synthetic
invocations pass. Synthetic crossing/sparse dynamic rows vary up to about5% slower; anomalously
slow parent memo rows are retained as raw samples and do not support a speedup claim.

Existing complete-plan/memo tests cover default/refused lookups, copied handles, detached source
lifetimes, shared occupancy, source/cycle-policy identity, callback handle replacement and paid
fault/retry state. Selected invocation-cache and host memory-reentry suites remain controls.
Pinned formatting and the benchmark parser tests accompany those native checks.

Exact hashes, C lowering evidence, build commands and full samples remain under
`build/pvm11/pricing-borrows/`. Results are Apple M1 Max/macOS checked ARC/Clang ThinLTO observations;
Linux performance and whole-JAM/STF parity remain open. M1 framing is complete within its existing
scope; full state serialization remains open. Fuzzing remains paused pending Daybreak access.
