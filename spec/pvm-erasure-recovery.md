# Bounded erasure chunk recovery

Target GP [`dc9a3bf79acd044ac004f756cff88a8acc9c416d`](https://github.com/gavofyork/graypaper/blob/dc9a3bf79acd044ac004f756cff88a8acc9c416d/text/erasure_coding.tex) erasure_coding.tex, recovery
function and Generator Polynomial; JAMNP-S aa0e2b8498c0b1bc1725af2903704d701c6577ab
CE133/138/139/140 fallback requires this computation. Accept exactly the geometry's
recovery threshold of distinct indexed chunks in arbitrary order. Chunks consist
of little-endian Cantor-coordinate words. Reconstruct systematic rows in index order,
check recovered zero padding, and return the independently declared original length.

Convert each validator ordinal to its evaluation point and append the d'-d
implicit zero points. Use Newton divided differences at the resulting d' points.
Precompute inverses for the distinct nonzero XOR differences, each costing 31
products. For k word columns and m missing original rows, total products are
31*distinctDifferences + k*(d'*(d'-1)/2 + m*(d'-1)). When all systematic rows
are supplied, copy them exactly without field operations.
Precharge all variable output/workspace buffers and products before allocation or
field operations. Fixed scratch includes 512 coordinates and 2048 difference flags. Payloads are capped
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
