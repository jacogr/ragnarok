# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Trie membership alone cannot certify a stored preimage's advertised content hash.
import std/[assertions, syncio]
import ../../support/proof_service_helpers
import ../../../src/state/proof/[service as proof_service, view as proof_view]
import ../../../src/state/trie_proof
import ../../../src/codec/bounded
import ../../../src/codec/state/[accounts as state_accounts, layout as state_layout,
    trie as state_trie, service_values as state_service_values]
import ../../../src/crypto/primitives
proc main() =
  ## Verify real small and empty preimages, and authenticate deliberately inconsistent state separately.
  let service = ServiceIndex(7)
  let account = serviceMetadataEntry(service, ServiceMetadata(), ByteLimit(105)).value
  let limits = ServiceEntryLimits(keyBytes: ByteLimit(32), valueBytes: ByteLimit(4))
  for bytes in [@[byte 1, 2, 3, 4], newSeq[byte](0)]:
    # Both key and value hashing use the maintained primitive; no default digest becomes authority.
    let hash = ServicePreimageHash(array[32, byte](blake2b256(bytes).value))
    let row = servicePreimageEntry(service, hash, bytes, limits).value
    let view = serviceView(@[account, row], [account.key, row.key])
    assert view.readProofPreimage(service, hash, ByteLimit(4)).value.bytes == bytes
    assert serviceView(@[account, row], [account.key]).readProofPreimage(service, hash, ByteLimit(
        4)).error == ServiceProofError.MissingWitness
    assert serviceView(@[account], [account.key, row.key]).readProofPreimage(service, hash,
        ByteLimit(4)).error == ServiceProofError.AbsentValue
    assert serviceView(@[row], [account.key, row.key]).readProofPreimage(service, hash, ByteLimit(
        4)).error == ServiceProofError.AbsentValue
    if bytes.len != 0:
      # A short response quota refuses before copying or hashing the stored content.
      assert view.readProofPreimage(service, hash, ByteLimit(3)).error ==
          ServiceProofError.LimitExceeded
    let malformed = StateEntry(key: row.key, value: @[byte 255])
    assert serviceView(@[account, malformed], [account.key, row.key]).readProofPreimage(service,
        hash, ByteLimit(4)).error == ServiceProofError.InvalidValue
  let missingView = default(ProofView)
  let missingHash = default(ServicePreimageHash)
  assert missingView.readProofPreimage(service, missingHash, ByteLimit(4)).error ==
      ServiceProofError.Uninitialized
  echo "state-proof-service-preimage: ok"
main()
