# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Proof-backed reads retain exact old revisions after complete-map publication and owner release.
import std/assertions
import std/syncio
import ../../support/state_proof_service_helpers
import ../../../src/state/store as state_store
import ../../../src/state/snapshot_proof as state_snapshot_proof
import ../../../src/state/proof_service as state_proof_service
import ../../../src/state/proof_view as state_proof_view
import ../../../src/state/trie_proof as state_trie_proof
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/state_accounts as codec_state_accounts
import ../../../src/codec/state_layout as codec_state_layout
import ../../../src/codec/state_trie as codec_state_trie
import ../../../src/codec/state_service_values as codec_state_service_values
proc verified(snapshot: StateStoreSnapshot, plan: ServiceProofPlan): ProofView =
  ## Generate from a complete owner and independently authenticate every response under its retained root.
  let proofs = generateServiceProofs(snapshot, plan, mapLimits, proofLimits, batchLimits).value
  var queries: seq[StateProofQuery] = @[]
  for i in 0..<proofs.len: queries.add(proofs.queryAt(i).value)
  verifyServiceProofs(plan, queries, snapshot.commitment.root, proofLimits, batchLimits,
      viewLimits).value
proc main() =
  ## A changed/deleted successor must neither rewrite old facts nor authenticate them under its new root.
  let service = ServiceIndex(7)
  let account = serviceMetadataEntry(service, ServiceMetadata(balance: AccountBalance(99)),
      ByteLimit(105)).value
  let storage = serviceStorageEntry(service, [byte 1], [byte 8], ServiceEntryLimits(
      keyBytes: ByteLimit(1), valueBytes: ByteLimit(1))).value
  let plan = planProofStorage(service, [byte 1], ByteLimit(1), ElementLimit(2)).value
  let policy = StateStoreLimits(trie: mapLimits, writes: ElementLimit(16),
      writeValueBytes: ByteLimit(16384))
  var store = newStateStore([account, storage], policy).value
  var original = store.snapshot.value
  let old = verified(original, plan)
  let wire = encodeServiceProofs(old, plan, viewLimits, proofLimits, ByteLimit(4096)).value
  let replacement = serviceMetadataEntry(service, ServiceMetadata(balance: AccountBalance(100)),
      ByteLimit(105)).value
  assert store.apply([StateWrite(key: account.key, kind: StateWriteKind.Put,
      value: replacement.value), StateWrite(key: storage.key,
      kind: StateWriteKind.Delete)]).error == StateStoreError.None
  let changed = store.snapshot.value
  let current = verified(changed, plan)
  assert uint64(current.readProofAccount(service).value.balance) == 100
  assert current.readProofStorage(service, [byte 1], ServiceEntryLimits(keyBytes: ByteLimit(1),
      valueBytes: ByteLimit(1))).error == ServiceProofError.AbsentValue
  let refused = decodeServiceProofs(wire, plan, current.root, viewLimits, proofLimits, batchLimits,
      ByteLimit(4096))
  assert refused.error == ServiceProofError.ProofFailure and refused.proofError ==
      StateProofError.RootMismatch
  original = default(StateStoreSnapshot)
  store = default(StateStore)
  assert uint64(old.readProofAccount(service).value.balance) == 99
  var detached = old.readProofStorage(service, [byte 1], ServiceEntryLimits(keyBytes: ByteLimit(1),
      valueBytes: ByteLimit(1))).value.bytes
  detached[0] = 99
  assert old.readProofStorage(service, [byte 1], ServiceEntryLimits(keyBytes: ByteLimit(1),
      valueBytes: ByteLimit(1))).value.bytes == @[byte 8]
  assert decodeServiceProofs(wire, plan, old.root, viewLimits, proofLimits, batchLimits, ByteLimit(
      4096)).error == ServiceProofError.None
  echo "state-proof-service-retention: ok"
main()
