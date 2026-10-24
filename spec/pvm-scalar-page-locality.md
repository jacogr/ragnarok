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
