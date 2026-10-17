# Work-package input codecs

Target: Gray Paper v0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401`. Normative definitions:
Appendix C.1/C.2 context/package/item and `I` import-reference encoding; reporting/assurance
`workcontext`; work-packages/reports `workpackage`, `workitem`, dependency bound,
`limitworkpackagebandwidth`, `checkextractsize`, `segmentfootprint` and `wplimits`; corresponding
constants in `definitions.tex`. Chapter and tiny/full JSON/binary hashes are in
[pins.json](pins.json).

## Wire and nominal domains

`RefinementContext` owns the same anchor/root/slot nominal domains as existing reports. Its fixed
prefix is 168 bytes: anchor32, E4 anchor slot, posterior state root32, accumulation root32,
lookup anchor32, E4 lookup slot and lookup posterior state root32. A canonical natural prerequisite
count and strictly ascending unique package hashes follow. At most eight prerequisites are accepted.
`decodeRefinementContext` returns the complete fixed value and consumed prefix without allocation.
Tests compare its fixed bytes with the existing report header's context at offset 104; report
behavior and public types are unchanged.

`ImportReference` is an owned tagged union. Root references contain a nominal `SegmentRoot`;
package references contain a nominal `PackageHash`. Both use a nominal `ImportIndex`. Wire is the
selected hash32 followed by E2: lower 15 bits are the index, high bit selects package hash when
set and segment root when clear. There is no extra tag octet. Every packed E2 value has exactly
one alternative. Typed source indices above 32767 reject before encoding. Index eligibility in
the actual referenced export tree and package-to-root lookup remain contextual checks.

`ExtrinsicCommitment` is an owned nominal data hash32 plus nominal E4 preimage byte length.
Standalone commitment codecs accept the full E4 length range; enclosing items/packages account
for the full advertised size under the bundle footprint limit. Preimage availability, length and
hash agreement are checked later against actual external input data.

`WorkItem` wire is E4 destination service, code hash32, E8 refinement gas, E8 accumulation gas,
E2 export count, variable payload, variable import references and variable extrinsic commitments.
Each variable term has one canonical natural length/count. Import and commitment sequences
preserve supplied order and duplicates; they are not sets and are never silently sorted.

`WorkPackage` wire is E4 authorization-code host service, authorization-code hash32, complete
context, variable authorization token, variable authorizer configuration, and a nonempty variable
sequence of complete items. The source host has its own nominal type, separate from item service
indices. Code hashes reuse the existing code-hash domain, rather than the distinct derived
`AuthorizerHash` used in reports. Code/configuration hashing is outside these codecs.

## Resource policy

Both standalone and package item paths enforce compatible structural limits. Packages have 1..16
items. Across the package: imports <=3072, exports <=3072, input commitments <=128. An item's
corresponding counters cannot exceed those totals. Every canonical count is bounded before
narrowing, indexing, multiplication or any input-derived allocation.

Distinct **tagged package identities** across all item imports consume dependency slots; repeated
references to the same package, even at different segment indices, consume one slot. Direct roots
consume none. The dependency equation adds that distinct-import count to the explicit prerequisite
count, for a maximum of eight. It does not union the two sets: an identity present in both still
contributes once in each term. Prerequisite hashes alone require canonical set order.

The normative footprint is authorization bytes + configuration bytes + all payload bytes +
4488 times the import count + every advertised extrinsic input length, at most **13,791,360**.
The import footprint includes a 4104-byte segment and 384 bytes of proof hashes. This follows the
explicit `checkextractsize` formula; it is separate from the encoded package's actual byte length.
A tiny wire frame advertising huge external input still fails the footprint bound. Full E4/E8
values are checked before host conversion/addition; aggregate addition uses remaining-budget
subtraction so sums cannot wrap.

`PackageConfig` supplies explicit refinement/accumulation gas ceilings and a serialized `maxBytes`
policy. Both gas sums must be **strictly below** their configured ceilings, following `wplimits`.
Zero ceilings are invalid configurations. `fullPackageConfig(maxBytes)` selects the published
5,000,000,000 refinement and 10,000,000 accumulation ceilings. Other chain profiles supply their
actual parameters explicitly. The gas domain remains the existing nominal `Gas` unit. Standalone
items use one item's package-compatible resources with no authorization/context costs. The fixed
context/import/commitment APIs require no chain configuration.

`maxBytes` limits only the consumed serialized prefix; unrelated trailing bytes do not consume it.
It does not replace the normative footprint formula. Stateless codec acceptance does not establish
historical anchor eligibility, service/code availability, import resolution/proofs, authorization,
refinement execution or external-data correctness.

## Ownership, atomicity and failures

Encoding sources own fixed fields and borrow their public sequences for the synchronous call.
Callers keep sources stable. Preflight validates every context/item field, canonical set, count,
resource aggregate and byte extent before output capacity/alias checks and any write. The whole
written destination must be disjoint from outer descriptors, all item records, authorization and
configuration blobs, and every nested payload/import/commitment sequence. A late source failure
cannot emit an earlier host, context or item. Unused destination suffix bytes are unchanged.
The standalone fixed encoders also reject source overlap before writing.

Decoding scans first into fixed private metadata (at most sixteen items and eight dependencies),
without input-derived allocation. Fixed extents check input availability before the serialized
budget; count framing checks canonicality before prefix budget and count bound. Context ordering
is checked before a package's authorization/items. Import dependencies are checked while scanning
imports; item count/gas/payload costs follow complete manifest framing, then segment-proof costs
and advertised extrinsic lengths. Failed scans discard all progress and never publish an owner.
Only complete validation authorizes capture of the exact prefix into private acyclic ARC storage.
Input stays stable during the call. Allocation exhaustion retains Nim's existing fail-stop policy.

`OwnedWorkPackage` retains wire and matching metadata privately. `workPackageInfo` returns copied
fixed metadata; `copyPackageBlob` selects only a named authorization/configuration blob.
`workItemAt` returns an `OwnedWorkItem` retaining the **same parent snapshot** with a private index.
The child survives release of every package handle and source buffer; no second buffer can be
paired with its private coordinates. Standalone item decoding uses the same retained representation.
`workItemInfo`, `importAt` and `extrinsicAt` return fixed value copies; `copyItemPayload` extracts
through its matching item owner. No mutable wire, backing pointer or detached span is exported.
Owner re-emission and copies validate complete destination capacity before writing and reject
written destinations overlapping any retained wire bytes. Default owners and signed invalid
indices fail. Every failed/default result carries only its reason, never values or progress.
On Nimony, private result/variant storage and success/selected-kind accessors protect both result
values and import identity alternatives.

## Verification

Run `python3 tests/test_package_harness.py` and `python3 tests/test_work_package.py`. Published
context/item/package JSON reconstructs both tiny/full binary profiles exactly. Native encoder
sources are constructed directly from named fields; decoder observations check each field and
manifest element independently, alongside owner re-emission. Test-owned input is overwritten after
capture, copied getters are mutated, and retained child handles outlive their parent handles.

Coverage includes E2/E4/E8 and natural-width boundaries; all representative truncations; empty
blobs; exact/short/spare capacities and serialized byte budgets; minimum/maximum/excessive counts;
strict gas boundaries and uint64 aggregate-overflow attempts; inclusive footprint maxima including
3072 import proofs; cross-item totals; distinct/repeated import dependencies and prerequisite
interaction; malformed/overlong/huge count prefixes; deterministic structured/random input;
late-source atomicity; descriptor/blob/import/commitment aliases; runtime variant guards;
four nominal compiler rejection probes and two private-owner probes. Eight independent harness
known-answer tests protect the Python oracle. The established Linux CI profile belongs to the
Nim 2 baseline; the experimental Nimony port has not switched or passed that pipeline.

## Nimony port verification

The pinned nightly uses private `PackageResult[T]` status/value storage and read-only outcomes.
`value` requires success for fixed records, metadata, owner handles and byte progress. Package/
item references are private nullable ARC handles with stable local nil proofs before access;
item indices are private and cannot be rebound. Capture, limits, preflight ordering and wire
formats remain unchanged.

`ImportReference.kind` is read-only. `root` requires Root; `package` requires Package. Both return
copied nominal identities. Typed `rootImport`/`packageImport` factories preserve those domains;
indices above 32767 still fail encoding preflight. The default remains a zero-index Root. Safe
callers cannot retag or forge raw alternatives. The nominal wrong-identity probe uses the typed
factory, preserving a real domain-mismatch check independently of read-only-property rejection.

`tools/test_nimony.py` runs all 8,123 existing requests across context/import/commitment/item/
package APIs. Published tiny/full bytes, full independently observed fields, source mutation,
footprint/gas/dependency/count limits, malformed inputs and atomic destinations retain coverage.
The adapter uses concrete fixed-record branches after this nightly rejected its template binding;
all original operations remain covered. Blob roles are explicitly iterated in their original order.

The native suite retains all alias probes using writable fixed-array views over actual backing
allocations. It adds parent replacement, orphan child extraction/re-emission and independent
copied identities. A warmed 1,000-cycle ARC workload leaves public live occupancy at 30,400 bytes
on the trial Mac; outer fixtures stay live. This measures that workload, not RSS or general leak
freedom. Fifty-one runtime misuse checks guard every public result instantiation and wrong import
alternatives. Nineteen compilation checks reject result/owner/variant bypasses; four nominal
checks protect import indices, host services, reference identities and commitment lengths.

Commands, compiler metadata, source/corpus hashes and exact diagnostics are recorded in ignored
`build/nimony-trial/verification/results.json` and adjacent logs. Local checked ARC/Clang LTO parity
does not establish Linux or full-client migration; see [the trial](../docs/nimony-trial.md).
