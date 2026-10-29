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
  let raw = @[byte 1, 2, 3]
  let derived = serviceStorageKey(service, raw, ByteLimit(3)).value
  let plan = planProofStorage(service, raw, ByteLimit(3), ElementLimit(2)).value
  assert plan.valid and plan.len == 2
  var matched = false
  var account = false
  for i in 0..<plan.len:
    # Fixed identities are inspected without exporting the retained mutable key sequence.
    let key = array[31, byte](plan.keyAt(i).value)
    if key == array[31, byte](derived): matched = true
    if key == array[31, byte](chapterServiceKey(StateChapter(255), service)): account = true
  assert matched and account
  assert planProofStorage(service, raw, ByteLimit(2), ElementLimit(2)).error ==
      ServiceProofError.LimitExceeded

  echo "state-proof-plan-storage: ok"
main()
