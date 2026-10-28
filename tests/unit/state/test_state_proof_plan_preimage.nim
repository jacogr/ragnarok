# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

import std/assertions
import std/syncio
import ../../../src/state/proof_service as state_proof_service
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/state_accounts as codec_state_accounts
import ../../../src/codec/state_layout as codec_state_layout
import ../../../src/codec/state_service_values as codec_state_service_values
import ../../../src/codec/state_requests as codec_state_requests
proc main() =
  ## Semantic selectors must request the account plus their exact namespace identity.
  let service = ServiceIndex(7)
  let hash = default(ServicePreimageHash)
  let derived = servicePreimageKey(service, hash, ByteLimit(32)).value
  let plan = planProofPreimage(service, hash, ElementLimit(2)).value
  assert plan.valid and plan.len == 2
  var matched = false
  var account = false
  for i in 0..<plan.len:
    # Fixed identities are inspected without exporting the retained mutable key sequence.
    let key = array[31, byte](plan.keyAt(i).value)
    if key == array[31, byte](derived): matched = true
    if key == array[31, byte](chapterServiceKey(StateChapter(255), service)): account = true
  assert matched and account
  assert planProofPreimage(service, hash, ElementLimit(1)).error == ServiceProofError.LimitExceeded

  echo "state-proof-plan-preimage: ok"
main()
