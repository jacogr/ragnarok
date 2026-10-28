# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Code reads derive identity from authenticated metadata instead of accepting a detached replacement hash.
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
import ../../../src/codec/state_requests as codec_state_requests
import ../../../src/crypto/primitives as crypto_primitives
proc main() =
  ## Correct content at an unrelated code hash never substitutes for the selected account's code.
  let service = ServiceIndex(7)
  let bytes = @[byte 4, 5, 6]
  let digest = array[32, byte](blake2b256(bytes).value)
  let hash = ServicePreimageHash(digest)
  let account = serviceMetadataEntry(service, ServiceMetadata(codeHash: CodeHash(digest)),
      ByteLimit(105)).value
  let blob = servicePreimageEntry(service, hash, bytes, ServiceEntryLimits(keyBytes: ByteLimit(32),
      valueBytes: ByteLimit(3))).value
  let history = serviceRequestEntry(service, hash, RequestLength(3), availableHistory(RequestSlot(
      4)), RequestEntryConfig(keyBytes: ByteLimit(32), history: RequestHistoryConfig(
      items: ElementLimit(3), maxBytes: ByteLimit(13)))).value
  let view = serviceView(@[account, blob, history], [account.key, blob.key, history.key])
  assert view.readProofCode(service, RequestSlot(4), ByteLimit(3)).value.bytes == bytes
  assert view.readProofCode(service, RequestSlot(3), ByteLimit(3)).error ==
      ServiceProofError.AbsentValue
  assert view.readProofCode(service, RequestSlot(4), ByteLimit(2)).error ==
      ServiceProofError.LimitExceeded
  assert serviceView(@[account, blob, history], [account.key, blob.key]).readProofCode(service,
      RequestSlot(4), ByteLimit(3)).error == ServiceProofError.MissingWitness
  let changed = serviceMetadataEntry(service, ServiceMetadata(), ByteLimit(105)).value
  assert serviceView(@[changed, blob, history], [changed.key, blob.key, history.key]).readProofCode(
      service, RequestSlot(4), ByteLimit(3)).error == ServiceProofError.MissingWitness
  assert default(ProofView).readProofCode(service, RequestSlot(4), ByteLimit(3)).error ==
      ServiceProofError.Uninitialized
  echo "state-proof-service-code: ok"
main()
