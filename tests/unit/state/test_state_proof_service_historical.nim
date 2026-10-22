# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Historical reads require same-root account, actual preimage content and actual-length request history.
import std/[assertions, syncio]
import ../../support/proof_service_helpers
import ../../../src/state/[proof_service, proof_view, trie_proof]
import ../../../src/codec/[bounded, state_accounts, state_layout, state_trie, state_service_values, state_requests]
import ../../../src/crypto/primitives
proc main() =
  ## Independently spell each interval's expected membership at exact boundary times.
  let service = ServiceIndex(7)
  let account = serviceMetadataEntry(service, ServiceMetadata(), ByteLimit(105)).value
  let bytes = @[byte 4, 5, 6]
  let hash = ServicePreimageHash(array[32, byte](blake2b256(bytes).value))
  let blob = servicePreimageEntry(service, hash, bytes, ServiceEntryLimits(keyBytes: ByteLimit(32),
      valueBytes: ByteLimit(3))).value
  let config = RequestEntryConfig(keyBytes: ByteLimit(32), history: RequestHistoryConfig(
      items: ElementLimit(3), maxBytes: ByteLimit(13)))
  let histories = [requestedHistory(), availableHistory(RequestSlot(4)), unavailableHistory(
      RequestSlot(4), RequestSlot(8)), reavailableHistory(RequestSlot(4), RequestSlot(8),
      RequestSlot(12))]
  let expected = [[false, false, false, false, false, false, false], [false, true, true, true, true,
      true, true], [false, true, true, false, false, false, false], [false, true, true, false,
      false, true, true]]
  let times = [3'u32, 4'u32, 7'u32, 8'u32, 11'u32, 12'u32, high(uint32)]
  for mode, history in histories:
    # The actual blob length chooses history, not an advertised caller hint.
    let row = serviceRequestEntry(service, hash, RequestLength(3), history, config).value
    let view = serviceView(@[account, blob, row], [account.key, blob.key, row.key])
    for i, time in times:
      let found = view.readProofHistoricalPreimage(service, hash, RequestSlot(time), ByteLimit(3))
      if expected[mode][i]:
        assert found.error == ServiceProofError.None and found.value.bytes == bytes
      else:
        assert found.error == ServiceProofError.AbsentValue
    assert serviceView(@[account, blob, row], [account.key, blob.key]).readProofHistoricalPreimage(
        service, hash, RequestSlot(4), ByteLimit(3)).error == ServiceProofError.MissingWitness
    assert serviceView(@[account, blob], [account.key, blob.key,
        row.key]).readProofHistoricalPreimage(service, hash, RequestSlot(4), ByteLimit(3)).error ==
        ServiceProofError.InvalidValue
  echo "state-proof-service-historical: ok"
main()
