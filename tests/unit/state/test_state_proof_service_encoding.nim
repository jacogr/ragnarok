# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

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
proc main() =
  ## The service response is the existing local envelope, with exact plan matching rather than a new protocol.
  let service = ServiceIndex(7)
  let account = serviceMetadataEntry(service, ServiceMetadata(balance: AccountBalance(99)),
      ByteLimit(105)).value
  let plan = planProofAccount(service, ElementLimit(1)).value
  let view = serviceView(@[account], [account.key])
  let root = view.root
  let encoded = encodeServiceProofs(view, plan, viewLimits, proofLimits, ByteLimit(4096)).value
  assert encoded == encodeProofView(view, viewLimits, proofLimits, ByteLimit(4096)).value
  assert encodeServiceProofs(view, plan, viewLimits, proofLimits, ByteLimit(encoded.len-1)).error ==
      ServiceProofError.LimitExceeded
  assert encodeServiceProofs(view, plan, viewLimits, proofLimits, ByteLimit(encoded.len)).value == encoded
  let other = planProofAccount(ServiceIndex(8), ElementLimit(1)).value
  assert encodeServiceProofs(view, other, viewLimits, proofLimits, ByteLimit(4096)).error ==
      ServiceProofError.InvalidInput
  let extra = serviceView(@[account], [account.key, chapterKey(StateChapter(11))])
  assert encodeServiceProofs(extra, plan, viewLimits, proofLimits, ByteLimit(4096)).error ==
      ServiceProofError.InvalidInput
  assert encodeServiceProofs(default(ProofView), plan, viewLimits, proofLimits, ByteLimit(
      4096)).error == ServiceProofError.Uninitialized
  assert uint64(view.readProofAccount(service).value.balance) == 99
  echo "state-proof-service-encoding: ok"
main()
