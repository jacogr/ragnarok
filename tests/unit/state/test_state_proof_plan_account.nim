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
  ## A copied plan shares immutable ownership while wrong ordinals remain typed refusals.
  let service = ServiceIndex(7)
  let plan = planProofAccount(service, ElementLimit(1)).value
  assert plan.valid and plan.len == 1
  assert array[31, byte](plan.keyAt(0).value) == array[31, byte](chapterServiceKey(StateChapter(
      255), service))
  assert plan.keyAt(-1).error == ServiceProofError.InvalidIndex
  assert plan.keyAt(1).error == ServiceProofError.InvalidIndex
  assert planProofAccount(service, ElementLimit(0)).error == ServiceProofError.LimitExceeded
  let empty = default(ServiceProofPlan)
  assert not empty.valid and empty.len == 0
  assert empty.keyAt(0).error == ServiceProofError.Uninitialized
  echo "state-proof-plan-account: ok"
main()
