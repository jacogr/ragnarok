# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Plan union coalesces common account dependencies without pretending to merge verified root facts.
import std/[assertions, syncio]
import ../../../src/state/proof_service
import ../../../src/codec/[bounded, state_accounts, state_layout, state_service_values]
proc main() =
  ## Exact unique budgets apply to output, while originals keep their independent immutable owners.
  let service = ServiceIndex(7)
  let account = planProofAccount(service, ElementLimit(1)).value
  let storage = planProofStorage(service, [byte 1], ByteLimit(1), ElementLimit(2)).value
  let preimage = planProofPreimage(service, default(ServicePreimageHash), ElementLimit(2)).value
  let joined = mergeProofPlans(storage, preimage, ElementLimit(3)).value
  assert joined.len == 3 and storage.len == 2 and preimage.len == 2
  assert mergeProofPlans(storage, preimage, ElementLimit(2)).error ==
      ServiceProofError.LimitExceeded
  assert mergeProofPlans(account, storage, ElementLimit(2)).value.len == 2
  assert mergeProofPlans(joined, joined, ElementLimit(3)).value.len == 3
  assert mergeProofPlans(default(ServiceProofPlan), joined, ElementLimit(3)).error ==
      ServiceProofError.Uninitialized
  assert mergeProofPlans(joined, default(ServiceProofPlan), ElementLimit(3)).error ==
      ServiceProofError.Uninitialized
  for i in 0..<storage.len:
    # Every source identity is retained exactly once in the union, regardless of source key order.
    var matches = 0
    for j in 0..<joined.len:
      if array[31, byte](storage.keyAt(i).value) == array[31, byte](joined.keyAt(
          j).value): inc matches
    assert matches == 1
  echo "state-proof-plan-union: ok"
main()
