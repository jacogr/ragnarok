# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

import std/[assertions, syncio, envvars]
import ../../../src/chain/[genesis, provider, state_proof]
import ../../../src/app/chain
import ../../../src/codec/[report_owned, header, bounded]
import ../../../src/codec/state/[layout as state_layout, trie as state_trie]
import ../../../src/state/[store, trie_proof]
import ../../../src/state/proof/service as proof_service
import ../../support/application_candidate_context
proc run() {.raises.} =
  ## Use the actual signed fixture's immutable selected posterior state.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var wire = newSeq[byte](raw.len)
  for i, octet in raw: wire[i] = byte(octet)
  let chain = initialized(fixture(decodeOwnedReport(wire, 2).value))
  let selected = chain.chainView.bestBlock
  let perProof = StateProofLimits(nodes: ElementLimit(249), valueBytes: ByteLimit(1000000))
  let aggregate = StateProofBatchLimits(items: ElementLimit(16), nodes: ElementLimit(3984),
      valueBytes: ByteLimit(16000000))
  assert selected.value.serviceCount > 0
  let service = selected.value.serviceAt(ServiceListIndex(0))
  let plan = planProofAccount(service, ElementLimit(1)).value
  let proofs = generateBlockServiceProofs(selected, plan, policy().trie, perProof, aggregate).value
  assert proofs.len == 1
  let query = proofs.queryAt(0).value
  assert array[31, byte](query.key) == array[31, byte](plan.keyAt(0).value)
  assert verifyBlockStateProof(selected, query.proof, query.key, perProof).value.present
  let invalid = default(GenesisResult)
  assert generateBlockServiceProofs(invalid, plan, policy().trie, perProof, aggregate).error ==
      StateProofError.Uninitialized
  let missing = default(ServiceProofPlan)
  assert generateBlockServiceProofs(selected, missing, policy().trie, perProof, aggregate).error ==
      StateProofError.Uninitialized
  echo "chain-state-proof-plan: ok"
try:
  run()
except:
  quit(2) # Missing or malformed signed fixture data must fail the suite.
