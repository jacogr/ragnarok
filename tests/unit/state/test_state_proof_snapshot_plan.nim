# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Semantic query plans drive complete snapshot generation without caller-supplied replacement keys.
import std/[assertions, syncio]
import ../../support/proof_service_helpers
import ../../../src/state/proof/service as proof_service
import ../../../src/state/[store, trie_proof, snapshot_proof]
import ../../../src/codec/bounded
import ../../../src/codec/state/[accounts as state_accounts, layout as state_layout,
    trie as state_trie, service_values as state_service_values]
proc main() =
  ## The account and storage selectors determine exactly two authenticated responses.
  let service = ServiceIndex(7)
  let account = serviceMetadataEntry(service, ServiceMetadata(), ByteLimit(105)).value
  let raw = @[byte 1]
  let storage = serviceStorageEntry(service, raw, [byte 8], ServiceEntryLimits(keyBytes: ByteLimit(
      1), valueBytes: ByteLimit(1))).value
  let store = newStateStore([account, storage], StateStoreLimits(trie: mapLimits,
      writes: ElementLimit(16), writeValueBytes: ByteLimit(16384))).value
  let source = store.snapshot.value
  let plan = planProofStorage(service, raw, ByteLimit(1), ElementLimit(2)).value
  let proofs = generateServiceProofs(source, plan, mapLimits, proofLimits, batchLimits).value
  assert proofs.len == plan.len
  for i in 0..<proofs.len:
    # Compare both the requested identity and its root-authenticated value.
    let query = proofs.queryAt(i).value
    assert array[31, byte](query.key) == array[31, byte](plan.keyAt(i).value)
    assert verifyStateProof(query.proof, source.commitment.root, query.key,
        proofLimits).value.present
  let invalid = default(ServiceProofPlan)
  assert generateServiceProofs(source, invalid, mapLimits, proofLimits, batchLimits).error ==
      StateProofError.Uninitialized
  var short = batchLimits
  short.items = ElementLimit(1)
  assert generateServiceProofs(source, plan, mapLimits, proofLimits, short).error ==
      StateProofError.LimitExceeded
  echo "state-proof-snapshot-plan: ok"
main()
