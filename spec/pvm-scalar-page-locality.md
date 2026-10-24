# Writer-owned scalar page locality

Each scalar memory writer retains two recent successful page-vector slots. An exact physical-page
index and an in-range slot must match before a hint can replace binary search. Hints retain only
integers, add no page/chunk owner or per-access allocation, and never imply presence, permission,
scalar width or valid address arithmetic. The original complete scalar preflight still determines
protected-prefix, wrapping, final-page presence and cross-page presence/permission precedence.

Only a completely successful preflight refreshes hints. A crossing keeps both touched slots;
a one-page operation retains the previous other slot. Writer aliases share metadata with the same
mutable writer identity. Epoch publication transfers the same sorted page vector, so retained
positions remain valid after sealing. Other immutable memory owners cannot replace the writer's
private base. New writers start with explicit invalid hints; metadata never crosses writer/program/
host-response ownership. Source/snapshot bytes and scalar failure behavior remain unchanged.

Compile-time boolean specialization leaves immutable scalar calls on their original binary-search
path without hint probes. Writer calls share the same preflight algorithm and select checked hints.
The first runtime-default variant caused a host-workload regression; it was rejected in favor of
this specialized implementation. No bounds/assertion, ARC, gas or protocol/dependency pin changes.

Native tests interleave three sparse pages (exceeding two slots), snapshot every write, retain an
earlier epoch and alias the writer. They verify cold/hot exact tags, cached read-only refusals,
absent physical pages, invalid widths, protected and high wrapped addresses, final-page overflow,
and missing-second-page precedence after warming a read-only first page. All original source
images survive unchanged. These pressure lifetimes join1,000 ARC release cycles. The source-owned
privacy rejection requires nonzero compiler exit plus the exact inaccessible `recent` field diagnostic.
Affected memory/execution/host/retry consumers and both maintained interpreter benchmarks cover
integration. Python logic is unchanged from the preceding928-test verification; inventory and
production Smoke are refreshed for the new source-owned guard and production code.

Initial matched checked M1 Max observations measured real-sieve CPU19.635→18.535 ms (~5.6% lower).
Sparse aligned/crossing scalar elapsed times were about24%/35% lower; ordinary/host workloads were
within roughly1.3% in that specialized pass. These are local workload observations, not whole-client
throughput, universal program equivalence or exact-head Linux CI. Final confirmation measured19.434→18.417 ms (~5.2% lower), with sparse aligned/crossing
elapsed times about24%/36% lower. Other ordinary/host differences were below3%. Complete
raw timing/state/source evidence is retained with the feature's verification artifacts.

M1 framing remains complete in its documented scope. Full state serialization and whole-block/JAM
parity remain open. Fuzzing remains deferred pending maintainer Daybreak access.

## Read/write preflight specialization, 2026-10-24

Every immutable/writer scalar load and store supplies a fixed read/write choice to
its private preflight. Specialize that choice alongside the existing hint choice,
so loads do not carry write-permission branches. All four combinations still use
one preflight source; no runtime mode is added and no public API or stored fact
changes. Width/owner validation, low-address protection, exclusive-end overflow,
complete presence checks and GP-PVM-008 permission precedence remain in their
original order. Failed writes still precede page/chunk mutation or hint refresh.

The selected qualification covers all4,050 independent memory-access rows, the
separate protected/high/wrapping boundary corpus, writer read/write/epoch matrices,
ordinary/fallible nested host reentry and mixed pricing. Writer and host ownership
groups retain1,000 balanced ARC cycles. Broad paired guest and synthetic timing,
calibrated census and pinned formatting must qualify the final build; a smaller
struct or fewer source branches alone is not evidence of speed.

Two preceding hypotheses were rejected: an eight-slot direct page-hint table showed
no Pinky gain (+1.0% in its bounded screen), and a compact40→24-byte private span
was neutral (-0.4%). Each passed936 control invocations, but neither is included.
The original two recent slots and native-width scalar span representation remain.

The final checked ARC/Clang ThinLTO build passes1,092 complete-state real-guest
invocations in two opposite process orders (three warmups, ten measured samples per
process). On M1 Max/macOS, indirect-call100,000 CPU medians in milliseconds are
25.103→24.017 dynamic (-4.3%),25.117→23.812 complete-plan (-5.2%) and25.488→24.316
memo (-4.6%). Two separate936-invocation control comparisons support that direction;
the final repeat measures3.4–4.7% lower times across those three modes. Sieve changes,
Pinky changes of roughly1.8% slower to3.3% faster, and smaller memory-fill differences
are not claimed as general improvements. The initial+6.0% sieve-memo cell does not
repeat (+0.6% in the final control), and remains in the raw report.

Two synthetic comparisons each pass1,716 validated invocations. Crossing-memory
elapsed medians improve by roughly5–10% in the repeated pricing cells; dynamic
aligned-memory and sparse-memory cases also improve. There is a reproducible
tradeoff: aligned-memory memo pricing changes48.625→53.209µs (+9.4%) in the repeat,
following+8.7% initially. This regression is retained explicitly for review rather
than hidden behind aggregate gains. Several other small cells vary by a few percent
or one timing quantum; there is no universal workload/policy improvement claim.

The scoped writer/independent-access/boundary/host-reentry/mixed-policy native suites,
429 calibrated census invocations, nine Python guard tests, inventory and pinned
formatting pass. The qualified pair is`build/pvm12/preflight-final-paired.json`,
with controls, synthetic first/repeat records and exact source/binary hashes under
`build/pvm12/`. An earlier partial run overlapped brief Python/inventory checks and
was stopped; it is diagnostic-only and contributes no acceptance timing. All final
timing passes exclude concurrent local builds/checks. These observations establish
local interpreter behavior, not exact-head Linux performance or whole-JAM throughput.
