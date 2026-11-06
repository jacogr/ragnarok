# Bounded erasure chunk recovery

Target GP fad0ded4a433052397bf7234352a57fe491883f7 erasure_coding.tex, recovery
function and Generator Polynomial; JAMNP-S aa0e2b8498c0b1bc1725af2903704d701c6577ab
CE133/138/139/140 fallback requires this computation. Accept exactly the geometry's
recovery threshold of distinct indexed chunks in arbitrary order. Chunks consist
of little-endian Cantor-coordinate words. Reconstruct systematic rows in index order,
check recovered zero padding, and return the independently declared original length.

Use Newton divided differences at the supplied distinct points. Precompute inverses
for the distinct nonzero XOR differences of supplied indices (at most 1023); every
inverse costs 31 products. Already supplied systematic rows are copied exactly.
For k word columns, d original rows and m>0 missing original rows, complete products
are 31*distinctDifferences + k*(d*(d-1)/2 + m*(d-1)); when m=0 no field products occur.
Precharge all variable output/workspace buffers and products before allocation or
field operations. Fixed scratch stays bounded by 2047 booleans. Payloads are capped
by the GP full bundle ceiling, validated before arithmetic and native narrowing.

This detached arithmetic result provides no authenticity or availability certificate.
Consumers must independently verify reconstructed segments/proofs or the full bundle
against the selected report. Execute recovery under the managed CPU lease; actual
network fallback scheduling remains in the JAMNP-S implementation work.

Completion: independent frozen Lagrange codewords at 6/9/51/1023 validators, all-parity,
mixed and permuted-systematic subsets, full 4104-byte segment geometries, non-divisible
bundle padding, exact budgets, hostile counts/indices/extents/padding, immutable output
and repeated ARC release. Retain existing encoder, bundle and export consumers.

Observed local evidence: `pvm_erasure_recovery` passes every frozen-codeword,
full-segment, padding, extent/index and exact-budget case. Its 1000 cycles include
successful recovery, copied output and post-allocation padding refusal; occupied ARC
remains 464 bytes. Existing word, bundle and export erasure suites pass with unchanged
ARC usage over 1000 cycles. Production ARC/LTO build, final formatted semantic/native
checks, stable formatter check and inventory pass. These are scoped local results;
network recovery scheduling and exact-head Linux CI remain separate.
