# Complete prepared execution and lookup profile

This opt-in experiment now exposes a complete prepared execution lifecycle around the
production interpreter. It supports all decoded instructions, register/control/memory
single stepping, bounded execution, response-only and typed fallible host callbacks,
page repair/retry, and fresh invocation state over reused code and pricing. It emits
neither native code nor fused instructions. Production source and toolchain pins remain
unchanged; this is an experimental generated module, not an installed production API.

## Ownership, admission and pricing

`prepareExecution(program, limits)` captures one exact immutable program owner and a
fixed pricing policy. `bindPrepared(code, source)` requires that exact owner, including
when another owner contains identical bytes. An overload accepts memory and CPU values
and constructs a source from the private owner. Every execution starts fresh CPU,
memory staging and attempt budgets; retaining or copying a handle does not retain an
in-progress mutable execution cursor. Successful result extraction requires checking
the private error discriminator. Default handles and failed results are not runnable.

`PricingMode.Lazy` uses production `GasMemo`, learns only successful prices of reached
blocks, and preserves runtime cycle-limit/refusal behavior, including already charged
blocks with a zero simulation budget. Copies share monotone pricing facts and require
exclusive synchronous use, as specified by the production memo contract.
`PricingMode.Complete` uses production immutable `GasPlan` and prices every static block
before admission, including unreachable blocks. An unpriceable block refuses preparation
without publishing a partial executable. Both policies keep their cycle limit fixed.

Admission checks code bytes, operation count, static block count and combined logical
payload before allocation. Hard maxima are 1 MiB code, 65,535 decoded instructions,
65,535 blocks and 16 MiB logical payload; callers can lower every ceiling. The default
per-block simulation ceiling is 1,000,000 cycles. The uint16 byte-PC map uses zero for
operand bytes and one-based indexes for instructions. Logical payload includes that
map, decoded records and the price table; allocator metadata, spare sequence capacity,
and the already retained program allocation are excluded. These limits do not bound RSS.

The sieve contains 157,152 code bytes and 38,590 decoded instructions. Full preparation
retains 4,041,280 logical bytes, including 1,257,216 price bytes; pricing alone retains
1,257,216 bytes. Complete pricing costs about 10 ms CPU to prepare; complete prepared
execution costs about 12 ms. Lazy pricing initialization alone costs about 0.1 ms and
learns reached prices inside the first execution. All warm comparisons exclude preparation.

## Correctness evidence

The generated module preserves production semantic bodies and changes cache storage,
lookup and parameter ownership. Both host callback templates retain production
transition/publication logic. Thirteen existing suites replay through a prepared
invocation facade with unchanged expectations: arithmetic/control stepping, every scalar
memory width, execution/cache behavior, both host outcomes, gas, memory replacement,
and independent memory-access, mixed-program, destination and fault/retry corpora.
Copied host consumers change import paths only. The independent step corpus contains
186 traces, memory access 4,050 rows, destination 31,488 rows, and mixed programs cover
32 programs with 128 gas scenarios. General corpus replay uses lazy pricing to preserve
reachability-dependent cycle failures; it is not a proof that eager admission accepts
every corpus program.

Separate controls exercise both policies: default/invalid handles, owner identity and
lifetime, nominal limits, exact resource boundaries and refusals, host capability gates,
zero step/host budgets, typed callback errors including zero-valued reasons, source
snapshot preservation, reusable page repair and no double charging. Four replay suites
and the explicit controls also run under AddressSanitizer. Assertion sentinels must fail;
compile-negative controls check private ownership/result fields and nominal limit types.
Every timed sieve invocation checks exact gas, every register, every page byte and
permission, terminal CPU metadata, and unchanged original CPU/memory snapshots.

## Before profiling

Matched warm median process CPU milliseconds on M1 Max, frozen master
`8ec989d66b378ef0d877bc73388794182912b97a`, pinned Nimony 0.6.3
`4724f66c2e01b17810c844f26575b2317995fda2`, checked release ARC/Clang ThinLTO:

| Model | 1,000 | 10,000 | 100,000 | 10,000,000 |
| --- | ---: | ---: | ---: | ---: |
| PolkaVM interpreted | 0.484 | 2.033 | 6.178 | 377.178 |
| Master default | 0.581 | 3.915 | 19.285 | 1,527.441 |
| Master lazy pricing | 0.192 | 1.497 | 14.491 | 1,463.513 |
| Master complete pricing | 0.181 | 1.437 | 13.604 | 1,456.478 |
| Prepared lazy pricing | 0.205 | 1.696 | 16.797 | 1,746.820 |
| Prepared complete pricing | 0.201 | 1.657 | 16.271 | 1,739.505 |

Two reversed-order passes supply twenty measured samples for the small cases and four
for 10 million, after warmups. Code and pricing are reused between fresh invocation
states. PolkaVM explicitly uses its interpreter and reuses a module with a fresh instance
per invocation; that reuse boundary differs. The Rust guest includes result counting,
so these timings cannot be compared directly with upstream published benchmark numbers.

Pricing reuse accounts for the benefit here; full decoding initially adds overhead to
both matching production pricing policies. Complete pricing alone is already available
in master and was reported separately to PVM #8 with preparation and first-call costs.

## Profile and focused change

Separate macOS `sample` captures use four seconds at one-millisecond intervals while
running the 10-million sieve. In the initial prepared capture, instruction lookup
accounts for 798 of 3,232 top-of-stack samples (about 25%). Master spends roughly 10% of its samples in the decoder. Sampling is approximate, and the optimizer
inlines different semantic helpers in the two binaries; subtracting these percentages
is not an exact overhead decomposition. Setup and state checks account for only two
samples in each capture.

Generated C and ARM64 disassembly show that narrowing the nullable table into a local
non-null `let` creates an ARC-owning alias on every lookup. The hot path increments and
restores the table reference count, retains a destructor branch, saves registers, and
copies a 64-byte decoded result through stack storage. The compiler leaves this lookup
out of line despite its inline annotation.

The accepted change moves non-null narrowing into a borrowed helper parameter. The
invocation retains the table throughout the call; the lookup creates no local owning
alias. Checked byte-PC indexing, decoded-result contracts, invalid-PC fallback, guest
semantics and resource bounds remain enabled. This removes the per-lookup ARC writes
and lets the compiler inline lookup into execution. No unsafe pointer, cursor pragma,
manual ownership hook or check-disabling flag is introduced. The original lookup remains
a generator-only profiling control, with no runtime mode switch.

The first two matched screening passes measured about 13–14% less execution CPU at
100,000 and 10 million. Final matched results and the post-change profile are recorded
below. Deterministic hardware/cachegrind counters and hyperfine are unavailable on this
macOS host; call-stack samples, generated code inspection and repeated process CPU
measurements are the evidence, not an instruction-count claim.

## Reproduce

Use the repository-pinned compiler and pristine pinned PolkaVM source:

```sh
export NIMONY=/absolute/path/to/pinned/nimony
export POLKAVM_SOURCE=/absolute/path/to/pristine/pinned/polkavm
make -C experiments/pvm-ir full
make -C experiments/pvm-ir full-profile PROFILE_ARGS=--sample
```

`full` runs controls before the six-engine comparison. `full-controls` and
`full-benchmark` split those steps; benchmark-only refuses changed control sources.
`full-profile` requires matching controls and existing full benchmark fixture/probe
artifacts. It compiles original and borrowed lookup representations under the same
module identity and checked flags, restores the accepted generated source, then compares
both with master complete pricing. Each workload receives twenty measured samples after
six warmups across two reversed-order passes. `--sample` adds separate macOS CPU captures;
leave it unset for portable timing only. Instrumented runs never enter timing statistics.

Full evidence lives under ignored `build/pvm-ir-experiment/full/` and `profile/`: source
and binary hashes, compiler commands, controls, immutable fixtures, raw CPU/wall samples,
per-pass spreads and stack captures. Historical results remain historical; future master
or toolchain changes require rebuilding and rerunning matching controls/comparisons.

## Refreshed six-engine comparison

After the borrowing change, the same checked six-engine procedure measured these
warm median CPU milliseconds (twenty samples per small case; four at 10 million):

| Model | 1,000 | 10,000 | 100,000 | 10,000,000 |
| --- | ---: | ---: | ---: | ---: |
| PolkaVM interpreted | 0.473 | 2.042 | 6.162 | 370.017 |
| Master default | 0.566 | 3.816 | 18.754 | 1,500.650 |
| Master lazy pricing | 0.181 | 1.443 | 14.025 | 1,453.051 |
| Master complete pricing | 0.171 | 1.439 | 13.275 | 1,444.292 |
| Prepared lazy pricing | 0.171 | 1.427 | 13.664 | 1,456.591 |
| Prepared complete pricing | 0.167 | 1.403 | 13.856 | 1,474.465 |

This refreshed table places complete prepared execution about 4% above matching master
at 100,000 and about 2% above it at 10 million. Small differences between lazy/complete
or the smaller workloads should not be treated as established wins. This is a local
process CPU comparison, with preparation excluded and the same reuse-boundary caveats
as the initial table. The separately rebuilt original lookup below isolates the change
within one longer matched run rather than attributing cross-session drift to the code.

## Longer matched comparison and remaining costs

The final comparison rebuilds the original lookup from the generator's profiling-only
control. Its generated source is byte-identical to the earlier fully verified model.
Each cell below is a median of twenty measured CPU samples across two reversed-order
passes, with three warmups per pass. All models use the same complete-pricing policy,
guest, fixture state and checked release flags. CPU milliseconds:

| Sieve limit | Master complete | Original prepared | Borrowed prepared | CPU reduction versus original |
| ---: | ---: | ---: | ---: | ---: |
| 100,000 | 13.483 | 16.069 | 14.172 | 11.8% |
| 10,000,000 | 1,449.581 | 1,707.801 | 1,489.524 | 12.8% |

Per-pass medians and min–max CPU milliseconds make the remaining variability visible:

| Limit | Model | Pass 1 | Pass 2 | Min–max |
| ---: | --- | ---: | ---: | ---: |
| 100,000 | Master complete | 13.262 | 13.930 | 13.124–14.485 |
| 100,000 | Original prepared | 15.928 | 16.239 | 15.683–16.743 |
| 100,000 | Borrowed prepared | 14.386 | 14.111 | 13.801–14.778 |
| 10,000,000 | Master complete | 1,450.510 | 1,448.725 | 1,431.358–1,567.796 |
| 10,000,000 | Original prepared | 1,706.357 | 1,725.695 | 1,698.213–1,787.317 |
| 10,000,000 | Borrowed prepared | 1,499.710 | 1,488.979 | 1,474.432–1,532.330 |

The original prepared penalty falls from about 19% to 5% at 100,000 and from about 18%
to 3% at 10 million relative to matching master. Both pass orders improve over the
original model. This does not establish a net prepared-engine advantage over matching
master; pricing reuse remains independently useful.

Fresh separate captures contain 3,232 samples for original prepared execution, with
843 (26%) at the out-of-line lookup, versus 3,278 samples for the borrowed version.
The borrowed binary has no separate lookup symbol or per-lookup ARC alias operations
in its native assembly. Inlining moves its remaining lookup work into the execution
loop; an absent symbol does not mean lookup itself is free. The borrowed capture has
1,516 top-of-stack samples in the execution loop (46%), 545 in register evaluation
(17%), 254 in control mutation (8%) and 170 in executable-target opcode checks (5%).
Other prominent leaves are memory mutation, load/store, scalar-span checks and block
price lookup. These are mostly shared semantic helpers, with different inlining choices
from master. The profile does not yet isolate which explains the small remaining gap.

Keep this bounded ownership change. Further representation changes should first
separate remaining lookup/dispatch work from shared register, memory and control costs;
this increment does not change those semantic evaluators or claim that all residual
overhead has been removed. Logical table size and admission policy are unchanged.
