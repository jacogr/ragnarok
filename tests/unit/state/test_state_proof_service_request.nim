# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Request readers enforce the adopted namespace domain and exact canonical history framing.
import std/[assertions, syncio]
import ../../support/proof_service_helpers
import ../../../src/state/[proof_service, proof_view]
import ../../../src/codec/[bounded, state_accounts, state_layout, state_trie, state_service_values, state_requests]
proc main() =
  ## Maximum admitted length stays a scalar selector and never requests length-sized allocation.
  let service = ServiceIndex(7)
  let hash = default(ServicePreimageHash)
  let account = serviceMetadataEntry(service, ServiceMetadata(), ByteLimit(105)).value
  let config = RequestEntryConfig(keyBytes: ByteLimit(32), history: RequestHistoryConfig(
      items: ElementLimit(3), maxBytes: ByteLimit(13)))
  for length in [0'u32, 1'u32, high(uint32)-2]:
    for history in [requestedHistory(), availableHistory(RequestSlot(4)), unavailableHistory(
        RequestSlot(4), RequestSlot(8)), reavailableHistory(RequestSlot(4), RequestSlot(8),
        RequestSlot(12))]:
      # Shape and timeslot fields survive authentication without invented chronological restrictions.
      let row = serviceRequestEntry(service, hash, RequestLength(length), history, config).value
      let view = serviceView(@[account, row], [account.key, row.key])
      let found = view.readProofRequest(service, hash, RequestLength(length))
      assert found.error == ServiceProofError.None and found.value.state == history.state
      if history.state == RequestState.Reavailable:
        assert uint32(found.value.restoredAt) == 12
      assert serviceView(@[account], [account.key, row.key]).readProofRequest(service, hash,
          RequestLength(length)).error == ServiceProofError.AbsentValue
      assert serviceView(@[account, row], [account.key]).readProofRequest(service, hash,
          RequestLength(length)).error == ServiceProofError.MissingWitness
  for length in [high(uint32)-1, high(uint32)]:
    # Reserved selectors have input-error precedence even for default views.
    assert default(ProofView).readProofRequest(service, hash, RequestLength(length)).error ==
        ServiceProofError.InvalidInput
  let key = serviceRequestKey(service, hash, RequestLength(3), ByteLimit(32)).value
  for bytes in [newSeq[byte](0), @[byte 4], @[byte 1], @[byte 0, 0], @[byte 128, 0], newSeq[byte](14)]:
    # Authenticated malformed history bytes cannot impersonate requested or absent state.
    let view = serviceView(@[account, StateEntry(key: key, value: bytes)], [account.key, key])
    assert view.readProofRequest(service, hash, RequestLength(3)).error ==
        ServiceProofError.InvalidValue
  echo "state-proof-service-request: ok"
main()
