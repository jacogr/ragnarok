# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

import std/[assertions, syncio]
import ../../support/proof_service_helpers
import ../../../src/state/proof/[service as proof_service, view as proof_view]
import ../../../src/state/trie_proof
import ../../../src/codec/bounded
import ../../../src/codec/state/[accounts as state_accounts, layout as state_layout,
    trie as state_trie]
proc main() =
  ## A serialized proof carries no authority until the receiving root and exact query plan both agree.
  let service = ServiceIndex(7)
  let account = serviceMetadataEntry(service, ServiceMetadata(balance: AccountBalance(99)),
      ByteLimit(105)).value
  let plan = planProofAccount(service, ElementLimit(1)).value
  let view = serviceView(@[account], [account.key])
  let root = view.root
  let wire = encodeServiceProofs(view, plan, viewLimits, proofLimits, ByteLimit(4096)).value
  let decoded = decodeServiceProofs(wire, plan, root, viewLimits, proofLimits, batchLimits,
      ByteLimit(4096))
  assert decoded.error == ServiceProofError.None
  assert uint64(decoded.value.readProofAccount(service).value.balance) == 99
  let foreign = decodeServiceProofs(wire, plan, default(StateRoot), viewLimits, proofLimits,
      batchLimits, ByteLimit(4096))
  assert foreign.error == ServiceProofError.ProofFailure and foreign.proofError ==
      StateProofError.RootMismatch
  let other = planProofAccount(ServiceIndex(8), ElementLimit(1)).value
  assert decodeServiceProofs(wire, other, root, viewLimits, proofLimits, batchLimits, ByteLimit(
      4096)).error == ServiceProofError.InvalidInput
  assert decodeServiceProofs(wire, plan, root, viewLimits, proofLimits, batchLimits, ByteLimit(
      wire.len-1)).error == ServiceProofError.LimitExceeded
  let invalid = default(ServiceProofPlan)
  assert decodeServiceProofs(wire, invalid, root, viewLimits, proofLimits, batchLimits, ByteLimit(
      4096)).error == ServiceProofError.Uninitialized
  echo "state-proof-service-decoding: ok"
main()
