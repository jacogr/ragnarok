# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Repeated partial-view capture, union, projection and transport release every immutable ARC owner.
# @@Verification={"arc": "state_proof_view_lifecycle_arc_release"}
import std/[assertions, syncio]
import ../../../src/state/[trie_proof, proof_view]
import ../../../src/codec/[bounded, state_layout, state_trie, state_safrole]
import ../../support/arc_evidence
proc fail(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Refuse hashing while immutable read composition and encoding operate on retained facts.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Count actual primitive attempts instead of inferring hash-free behavior from results.
proc cycle() =
  ## All derived collections and detached export records leave scope before the next allocator observation.
  let key = chapterKey(StateChapter(11))
  let other = chapterKey(StateChapter(12))
  let limits = StateProofLimits(nodes: ElementLimit(249), valueBytes: ByteLimit(4))
  let aggregate = StateProofBatchLimits(items: ElementLimit(2), nodes: ElementLimit(2),
      valueBytes: ByteLimit(4))
  let budget = ProofViewLimits(items: ElementLimit(2), valueBytes: ByteLimit(4))
  let leaf = encodeStateLeaf(key, [byte 7, 0, 0, 0], ByteLimit(4)).value
  let root = StateRoot(array[32, byte](hashStateNode(leaf).value))
  let present = captureStateProof([leaf], [byte 7, 0, 0, 0], limits).value
  let absent = captureStateProof([leaf], [], limits).value
  let batch = verifyStateProofs([StateProofQuery(key: key, proof: present),
    StateProofQuery(key: other, proof: absent)], root, limits, aggregate).value
  let view = captureProofView(batch, root, budget).value
  fail(1) # Immutable projection, union and encoding must not consult the hash backend.
  let projected = projectProofView(view, [key], budget).value
  let merged = mergeProofViews(projected, view, budget).value
  let encoded = encodeProofView(merged, budget, limits, ByteLimit(500)).value
  var shortAggregate = aggregate
  shortAggregate.nodes = ElementLimit(1)
  let refused = decodeProofView(encoded, root, budget, limits, shortAggregate, ByteLimit(500))
  assert refused.error == ProofViewError.ProofFailure and refused.proofError ==
      StateProofError.LimitExceeded
  assert calls() == 0
  fail(0) # Wire decoding intentionally authenticates raw witnesses again under the supplied root.
  let decoded = decodeProofView(encoded, root, budget, limits, aggregate, ByteLimit(500)).value
  assert uint32(decoded.readProofTime.value) == 7 and not decoded.lookup(other).value.present
  var exported = exportProofQueries(decoded, budget).value
  exported[0].key = other
  assert decoded.lookup(key).value.bytes == @[byte 7, 0, 0, 0]
  assert projectProofView(view, [key, other], ProofViewLimits()).error ==
      ProofViewError.LimitExceeded
for i in 0..<25:
  cycle() # Warm the exact partial-view ownership graph before sampling live allocator bytes.
let before = getOccupiedMem()
for i in 0..<1000:
  cycle() # Success and refusal temporaries retire within each named scope.
let after = getOccupiedMem()
assert before == after
recordArcRelease("state_proof_view_lifecycle", 1000, before, after)
echo "state-proof-view-lifecycle: ok"
