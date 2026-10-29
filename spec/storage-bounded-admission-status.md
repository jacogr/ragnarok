# Bounded admission: completion and remaining gates

This bounded increment implements the [admission contract](storage-bounded-admission.md).
It removes complete detached record-batch retention from encoded image/publication admission,
preserving private immutable ownership, canonical formats and complete graph authority. See the
[measured qualification](storage-bounded-admission-qualification.md) and
[API/operator guide](storage-bounded-admission-usage.md) for evidence and reproduction.

## Completed boundary

| Boundary | Implemented behavior and focused witness |
| --- | --- |
| Structural preflight | Exact domains/extents/counts, budgets, topology/canonical fields, ordering/duplicates before crypto or callbacks; exhaustive finite prefix/malformed corpus |
| Record delivery | One detached locally verified record at a time, explicit nonnil callbacks/state, prepared capacity after structural preflight, typed consumer refusal, provisional prefixes |
| Image admission | Exact private cell capacity, every retained root/route/count/policy, union inventory, missing dependency/orphan refusal and independent held views |
| Publication | Private staged cells; full encoded integrity before base/generation/policy checks, quota before conflict, complete graph and touched-record/orphan checks before installation |
| Mutable ownership | Raw inputs still copied/revalidated; mutable source erasure and lookup copies cannot alter admitted owners; no exported trusted flag or private factory |
| Failure lifetime | Late hash, primitive refusal, quota/conflict and invalid graph leave no partial head or staged cell owners; repeated 1,000-cycle ARC witnesses |
| Disk authority | Valid outer checksums/bindings cannot hide corrupt inner records; strict and exact-prefix recovery preserve selected bytes and retire failed-open locks |
| Measurements | Reversed paired native orders, both producer directions, exact selected bytes/maps/releases, strict read-only evidence validation and separate scoped Linux resident-pressure outcomes |

All runtime changes are confined to `record_codec.nim` and `src/storage/node/repository.nim`. Compiler/provider
pins, checked ARC/Clang LTO, physical on-disk formats and default Perf Storage/Growth work are
unchanged. Optional paired targets reuse explicitly selected frozen local builds. They add no
routine CI matrix or timing samples. Local focused tests and exact-head scoped Linux evidence
have separate coverage; the qualification records their identities rather than treating local
checks as whole-project Linux CI.

## Remaining limits

Bounded transport delivery still materializes a complete immutable repository graph. Address
scratch for unordered duplicates, staged reference arrays, graph verification and retained cells
remain bounded by existing explicit policies, not by a page cache. The 131,072-entry macOS fixture
retains 74.2 MiB of live Nim allocation in both baseline and candidate. The peak improvement does
not reduce that retained floor or establish an out-of-core storage design.

Allocation exhaustion keeps the established fail-stop behavior; this increment adds no recoverable
allocator. Resident-pressure results apply only to the recorded workload, host enforcement and
observer deadline. A high-water RSS value alone does not qualify a deployment memory ceiling,
and an observer timeout is distinct from a local cgroup OOM kill. The qualification explicitly
records whether larger 128 MiB no-swap cases complete.

Trusted external checkpoint import, complete full/light state separation and protocol-level
state serialization retain their existing authority and integration gates. The documented
[M1 framing baseline and local validation migration parity](../docs/m1.md) remain complete for
their implemented scope, distinct from complete JAM state serialization and whole-client parity. This storage increment asserts no new M1 or
JAM/STF completion.

## Next bounded work

Use the refreshed allocation diagnosis and the peak-versus-retained results to select the next
storage increment: measure the retained cell/reference/index layout before changing it. Keep an
unchanged full-map/root/lifetime workload and compare whole-child peaks with retained live Nim
allocation. A smaller retained representation must preserve immutable independent views,
physical hash/edge distinctions, complete-root inventory and atomic failure. Do not infer a
specific packing benefit from the current RSS reduction.

If the intended requirement is a database larger than RAM, first specify bounded working-set
ownership, on-disk lookup and graph-verification authority, rather than extending these complete
in-memory admission claims. Keep allocation-failure recovery, power-loss behavior and protocol
consumer integration separately scoped. Reuse only affected optional reopen/pressure cases;
additional qualification must not lengthen ordinary merge-feedback workloads by default.
