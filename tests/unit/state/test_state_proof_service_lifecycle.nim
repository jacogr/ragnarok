# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Repeated full-source generation, partial typed reads, transport and refused work release every ARC owner.
# @@Verification={"arc": "state_proof_service_lifecycle_arc_release"}
import std/[assertions, syncio]
import ../../support/[proof_service_helpers, arc_evidence]
import ../../../src/state/[store, snapshot_proof]
import ../../../src/state/proof/[service as proof_service, view as proof_view]
import ../../../src/state/trie_proof
import ../../../src/codec/bounded
import ../../../src/codec/state/[accounts as state_accounts, layout as state_layout,
    trie as state_trie, service_values as state_service_values, requests as state_requests]
import ../../../src/crypto/primitives
proc fail(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Restore the real primitive after each deliberately refused operation.
proc failAfter(successful: cint) {.importc: "ro_blake_after", cdecl.}
  ## Refuse after successful verification prefix work, exercising rollback ownership.
proc cycle() =
  ## Every complete store, immutable plan, proof, view, response and failure temporary dies within this scope.
  let service = ServiceIndex(7)
  let bytes = @[byte 1, 2, 3]
  let digest = array[32, byte](blake2b256(bytes).value)
  let hash = ServicePreimageHash(digest)
  let account = serviceMetadataEntry(service, ServiceMetadata(codeHash: CodeHash(digest)),
      ByteLimit(105)).value
  let blob = servicePreimageEntry(service, hash, bytes, ServiceEntryLimits(keyBytes: ByteLimit(32),
      valueBytes: ByteLimit(3))).value
  let storage = serviceStorageEntry(service, [byte 1], bytes, ServiceEntryLimits(
      keyBytes: ByteLimit(1), valueBytes: ByteLimit(3))).value
  let history = serviceRequestEntry(service, hash, RequestLength(3), availableHistory(RequestSlot(
      4)), RequestEntryConfig(keyBytes: ByteLimit(32), history: RequestHistoryConfig(
      items: ElementLimit(3), maxBytes: ByteLimit(13)))).value
  let store = newStateStore([account, blob, storage, history], StateStoreLimits(trie: mapLimits,
      writes: ElementLimit(16), writeValueBytes: ByteLimit(16384))).value
  let source = store.snapshot.value
  let a = planProofStorage(service, [byte 1], ByteLimit(1), ElementLimit(2)).value
  let b = planProofHistorical(service, hash, RequestLength(3), ElementLimit(3)).value
  let plan = mergeProofPlans(a, b, ElementLimit(4)).value
  let proofs = generateServiceProofs(source, plan, mapLimits, proofLimits, batchLimits).value
  var queries: seq[StateProofQuery] = @[]
  for i in 0..<proofs.len: queries.add(proofs.queryAt(i).value)
  let view = verifyServiceProofs(plan, queries, source.commitment.root, proofLimits, batchLimits,
      viewLimits).value
  let wire = encodeServiceProofs(view, plan, viewLimits, proofLimits, ByteLimit(4096)).value
  let received = decodeServiceProofs(wire, plan, source.commitment.root, viewLimits, proofLimits,
      batchLimits, ByteLimit(4096)).value
  assert received.readProofCode(service, RequestSlot(4), ByteLimit(3)).value.bytes == bytes
  var detached = received.readProofStorage(service, [byte 1], ServiceEntryLimits(
      keyBytes: ByteLimit(1), valueBytes: ByteLimit(3))).value.bytes
  detached[0] = 99
  assert received.readProofStorage(service, [byte 1], ServiceEntryLimits(keyBytes: ByteLimit(1),
      valueBytes: ByteLimit(3))).value.bytes == bytes
  assert mergeProofPlans(a, b, ElementLimit(3)).error == ServiceProofError.LimitExceeded
  assert encodeServiceProofs(view, plan, viewLimits, proofLimits, ByteLimit(1)).error ==
      ServiceProofError.LimitExceeded
  failAfter(1)
  let refused = decodeServiceProofs(wire, plan, source.commitment.root, viewLimits, proofLimits,
      batchLimits, ByteLimit(4096))
  assert refused.error == ServiceProofError.ProofFailure and refused.proofError ==
      StateProofError.BackendFailure
  fail(0)
  assert view.readProofCode(service, RequestSlot(4), ByteLimit(3)).value.bytes == bytes
for i in 0..<25:
  cycle() # Warm the exact ownership and crypto paths before measuring live native allocations.
let before = getOccupiedMem()
for i in 0..<1000:
  cycle() # Include both successful transport/read work and quota/backend refusal cleanup.
let after = getOccupiedMem()
assert before == after
recordArcRelease("state_proof_service_lifecycle", 1000, before, after)
echo "state-proof-service-lifecycle: ok"
