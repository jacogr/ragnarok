# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Code dependency discovery uses authenticated metadata while retaining root-independent query semantics.
import std/assertions
import std/syncio
import ../../support/state_proof_service_helpers
import ../../../src/state/proof_service as state_proof_service
import ../../../src/state/proof_view as state_proof_view
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/state_accounts as codec_state_accounts
import ../../../src/codec/state_layout as codec_state_layout
import ../../../src/codec/state_service_values as codec_state_service_values
import ../../../src/codec/state_requests as codec_state_requests
proc main() =
  ## Account-only evidence can discover a next-round code plan without pretending to include its blob.
  let service = ServiceIndex(7)
  var code = default(array[32, byte])
  code[0] = 99
  let account = serviceMetadataEntry(service, ServiceMetadata(codeHash: CodeHash(code)), ByteLimit(105)).value
  let view = serviceView(@[account], [account.key])
  let plan = planProofCode(view, service, RequestLength(3), ElementLimit(3)).value
  let expected = planProofHistorical(service, ServicePreimageHash(code), RequestLength(3),
      ElementLimit(3)).value
  assert plan.len == 3
  for i in 0..<3:
    # Compare every canonical requested identity, not just the count or caller-supplied hash.
    assert array[31, byte](plan.keyAt(i).value) == array[31, byte](expected.keyAt(i).value)
  assert planProofCode(view, service, RequestLength(3), ElementLimit(2)).error ==
      ServiceProofError.LimitExceeded
  assert planProofCode(view, service, RequestLength(high(uint32)), ElementLimit(3)).error ==
      ServiceProofError.InvalidInput
  assert planProofCode(default(ProofView), service, RequestLength(3), ElementLimit(3)).error ==
      ServiceProofError.Uninitialized
  assert planProofCode(serviceView(@[], [account.key]), service, RequestLength(3), ElementLimit(
      3)).error == ServiceProofError.AbsentValue
  echo "state-proof-plan-code: ok"
main()
