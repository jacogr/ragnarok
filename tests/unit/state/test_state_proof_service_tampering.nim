# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Receiving service responses reject truncation, mutation, scope substitution and a failed later witness atomically.
import std/assertions
import std/syncio
import ../../support/state_proof_service_helpers
import ../../../src/state/proof_service as state_proof_service
import ../../../src/state/proof_view as state_proof_view
import ../../../src/state/trie_proof as state_trie_proof
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/state_accounts as codec_state_accounts
import ../../../src/codec/state_layout as codec_state_layout
import ../../../src/codec/state_trie as codec_state_trie
import ../../../src/codec/state_service_values as codec_state_service_values
proc main() =
  ## Two authentic requested facts make a late proof failure observable without accepting an earlier prefix.
  let service = ServiceIndex(7)
  let account = serviceMetadataEntry(service, ServiceMetadata(balance: AccountBalance(99)),
      ByteLimit(105)).value
  let storage = serviceStorageEntry(service, [byte 1], [byte 8], ServiceEntryLimits(
      keyBytes: ByteLimit(1), valueBytes: ByteLimit(1))).value
  let view = serviceView(@[account, storage], [account.key, storage.key])
  let plan = planProofStorage(service, [byte 1], ByteLimit(1), ElementLimit(2)).value
  let wire = encodeServiceProofs(view, plan, viewLimits, proofLimits, ByteLimit(4096)).value
  for size in 0..<wire.len:
    # Every strict prefix must fail, including cuts inside later proof nodes/value bytes.
    var prefix = newSeq[byte](size)
    for i in 0..<size: prefix[i] = wire[i]
    assert decodeServiceProofs(prefix, plan, view.root, viewLimits, proofLimits, batchLimits,
        ByteLimit(4096)).error != ServiceProofError.None
  for offset in 0..<wire.len:
    # Each independently mutated octet must be rejected by framing, exact scope or root authentication.
    var changed = wire
    changed[offset] = changed[offset] xor 1
    assert decodeServiceProofs(changed, plan, view.root, viewLimits, proofLimits, batchLimits,
        ByteLimit(4096)).error != ServiceProofError.None
  var suffixed = wire
  suffixed.add(0)
  assert decodeServiceProofs(suffixed, plan, view.root, viewLimits, proofLimits, batchLimits,
      ByteLimit(4096)).error == ServiceProofError.InvalidValue
  var queries = exportProofQueries(view, viewLimits).value
  let absent = serviceView(@[], [queries[1].key])
  queries[1] = exportProofQueries(absent, viewLimits).value[0]
  let late = verifyServiceProofs(plan, queries, view.root, proofLimits, batchLimits, viewLimits)
  assert late.error == ServiceProofError.ProofFailure and late.proofError ==
      StateProofError.RootMismatch
  assert uint64(view.readProofAccount(service).value.balance) == 99
  assert view.readProofStorage(service, [byte 1], ServiceEntryLimits(keyBytes: ByteLimit(1),
      valueBytes: ByteLimit(1))).value.bytes == @[byte 8]
  let original = decodeServiceProofs(wire, plan, view.root, viewLimits, proofLimits, batchLimits,
      ByteLimit(4096))
  assert original.error == ServiceProofError.None
  echo "state-proof-service-tampering: ok"
main()
