# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Solicitation is a composed verdict requiring positive evidence or authenticated absence.
import std/[assertions, syncio]
import ../../support/proof_service_helpers
import ../../../src/state/proof/[service as proof_service, view as proof_view]
import ../../../src/codec/bounded
import ../../../src/codec/state/[accounts as state_accounts, layout as state_layout,
    service_values as state_service_values, requests as state_requests]
proc main() =
  ## An empty encoded history is requested; a missing history needs an actual absence witness.
  let service = ServiceIndex(7)
  let hash = default(ServicePreimageHash)
  let length = RequestLength(3)
  let account = serviceMetadataEntry(service, ServiceMetadata(), ByteLimit(105)).value
  let config = RequestEntryConfig(keyBytes: ByteLimit(32), history: RequestHistoryConfig(
      items: ElementLimit(3), maxBytes: ByteLimit(13)))
  let key = serviceRequestKey(service, hash, length, ByteLimit(32)).value
  for history in [requestedHistory(), availableHistory(RequestSlot(4)), unavailableHistory(
      RequestSlot(4), RequestSlot(8)), reavailableHistory(RequestSlot(4), RequestSlot(8),
      RequestSlot(12))]:
    # Every nonempty history is not outstanding, independent of its current availability interval.
    let row = serviceRequestEntry(service, hash, length, history, config).value
    assert serviceView(@[account, row], [account.key, row.key]).proofPreimageRequested(service,
        hash, length).value == (history.state == RequestState.Requested)
  assert not serviceView(@[account], [account.key, key]).proofPreimageRequested(service, hash, length).value
  assert not serviceView(@[], [account.key]).proofPreimageRequested(service, hash, length).value
  assert serviceView(@[account], [account.key]).proofPreimageRequested(service, hash,
      length).error == ServiceProofError.MissingWitness
  assert default(ProofView).proofPreimageRequested(service, hash, length).error ==
      ServiceProofError.Uninitialized
  assert default(ProofView).proofPreimageRequested(service, hash, RequestLength(high(
      uint32))).error == ServiceProofError.InvalidInput
  echo "state-proof-service-requested: ok"
main()
