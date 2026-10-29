# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

import std/[assertions, syncio]
import ../../../src/state/proof/service as proof_service
import ../../../src/codec/bounded
import ../../../src/codec/state/[accounts as state_accounts, layout as state_layout,
    service_values as state_service_values, requests as state_requests]
proc main() =
  ## Semantic selectors must request the account plus their exact namespace identity.
  let service = ServiceIndex(7)
  let hash = default(ServicePreimageHash)
  let derived = serviceRequestKey(service, hash, RequestLength(3), ByteLimit(32)).value
  let plan = planProofHistorical(service, hash, RequestLength(3), ElementLimit(3)).value
  assert plan.valid and plan.len == 3
  var matched = false
  var account = false
  for i in 0..<plan.len:
    # Fixed identities are inspected without exporting the retained mutable key sequence.
    let key = array[31, byte](plan.keyAt(i).value)
    if key == array[31, byte](derived): matched = true
    if key == array[31, byte](chapterServiceKey(StateChapter(255), service)): account = true
  assert matched and account
  assert planProofHistorical(service, hash, RequestLength(3), ElementLimit(2)).error ==
      ServiceProofError.LimitExceeded
  assert planProofHistorical(service, hash, RequestLength(high(uint32)-1), ElementLimit(3)).error ==
      ServiceProofError.InvalidInput
  echo "state-proof-plan-historical: ok"
main()
