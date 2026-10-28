# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Service selectors retain their public errors while sharing generic immutable query mechanics.
import std/assertions
import std/syncio
import ../../../src/state/proof_plan as state_proof_plan
import ../../../src/state/proof_service as state_proof_service
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/state_layout as codec_state_layout
import ../../../src/codec/state_accounts as codec_state_accounts
proc main() =
  ## Combine explicit global/service identities without granting roots or widening a service selector.
  let service = planProofAccount(ServiceIndex(7), ElementLimit(1)).value
  let generic = service.toStateProofPlan
  assert generic.valid and generic.len == 1
  assert array[31, byte](generic.keyAt(0).value) == array[31, byte](service.keyAt(0).value)
  let time = captureStateProofPlan([chapterKey(StateChapter(11))], ElementLimit(1)).value
  let joined = mergeStateProofPlans(generic, time, ElementLimit(2)).value
  assert joined.len == 2 and generic.len == 1 and service.len == 1
  assert mergeStateProofPlans(generic, time, ElementLimit(1)).error == ProofPlanError.LimitExceeded
  assert not default(ServiceProofPlan).toStateProofPlan.valid
  assert default(ServiceProofPlan).keyAt(0).error == ServiceProofError.Uninitialized
  assert service.keyAt(-1).error == ServiceProofError.InvalidIndex
  assert service.keyAt(1).error == ServiceProofError.InvalidIndex
  assert mergeProofPlans(service, service, ElementLimit(1)).value.len == 1
  assert mergeProofPlans(service, service, ElementLimit(0)).error == ServiceProofError.LimitExceeded
  echo "state-service-proof-plan-adapter: ok"
main()
