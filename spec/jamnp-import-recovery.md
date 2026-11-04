# Source-bound import recovery

Target JAMNP-S aa0e2b8498c0b1bc1725af2903704d701c6577ab CE139/140/148 and Gray Paper
fad0ded4a433052397bf7234352a57fe491883f7, work-package imports, paged proofs and erasure coding.

A fallback descriptor must come from the selected canonical chain, not C(3) alone or peer-selected
metadata. Capture a bounded catalog under the managed graph lease. A C(10) assignment supplies its
report and original active roster only in the retained snapshot at its registration slot. A later
copy must not relabel it with a new epoch's keys. Missing registration history remains unavailable;
this bounded catalog does not claim archival coverage. Preserve the full six-field specifier and
original roster together. Direct-root imports can select any canonical report for that content,
deterministically oldest first; package-relative imports must also match the original package hash.
Identical exports from different packages are legitimate. The local metadata-retention horizon is
explicit, at least672 complete epochs to meet the GP minimum; expiry limits local coverage without
claiming that valid data ceases to exist afterwards.

Shard assignment is pinned NP `i=(cR+v) mod V`, using the report's core, original assurer ordinal
and threshold, even when that set has retired. Previous-rotation credential indices use the maximum
of original current/previous populations for structural decoding; the assurer set remains the
original current roster. All chapter bytes, decoded reports, scanned roster keys and selected
snapshots have explicit independent and aggregate ceilings. Allocation-free C(10) inspection and
validator-prefix inspection preflight the whole capture before allocating decoded owners.

Paired threshold reconstruction recovers the requested export and its combined proof-page row.
Decode exact canonical upper-path and page-leaf counts, reject nonzero padding, match the actual
leaf hash, rebuild the local constant-depth tree and verify the complete root-first GP path against
the source descriptor. Combined logical byte, field-product and hash/preimage caps include both
row reconstructions and final proof verification. Only a completely verified import escapes.

## Verification and remaining integration

Local pinned checked ARC/Clang suites passed: `jamnp_import_recovery`, `state_availability`,
`pvm_export_erasure` and `pvm_computed_report`. Coverage includes six-to-nine-validator transitions
with distinct epoch keys and previous-nine credential indices, original shard assignment, exact
aggregate caps, malformed late chapters, missing registration history, wrong package/population,
explicit retention expiry, systematic/parity/mixed/permuted inputs, the64-export page boundary,
partial pages,1023-validator parity recovery and local resource refusals. Maximum-population catalog
capture and recovery also passed on a512KiB raw thread, with all host ARC aliases frozen through
join. One thousand success/late-failure cycles retained786032 bytes before and after. Frozen export
and report controls retained746928 and957488 bytes respectively over their1000 cycles.

Formatting, inventory, application build and Linux-target semantic checking passed. Linux-target
checking is not native Linux CI. Existing scoped controls remain applicable to unchanged code.

Managed original-grant/catalog binding, CE139-first acquisition, per-piece CE140 authentication and
retry, whole-package completion, ordinary operator activation and real TLS fallback verification
remain required before this feature is complete. No detached arithmetic or framing result grants
report credentials or availability authority.
