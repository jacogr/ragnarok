# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Detached authentic successor responses survive source retirement but old/new evidence cannot cross independently retained actual roots.
# @@Verification={"arc":"state_current_logical_proof_roots_arc_release"}
import std/[assertions, envvars, syncio]
import ../../support/[current_repeated_logical_context, current_namespace_refresh_context,
    current_logical_proof_context, arc_evidence]
import ../../../src/state/[current_logical_refresh, current_logical, accumulation_current_update,
    proof_plan, planned_proof, proof_view, proof_global, trie_proof, store]
import ../../../src/chain/[provider, genesis]
import ../../../src/app/proof_query
import ../../../src/codec/[bounded, report_owned, state_layout, state_trie]
type Detached = object ## Only independent scalar expectation, detached transport response and semantic request survive; no logical/view/snapshot owner escapes.
  expected: StateRoot
  response: ProofResponse
  plan: StateProofPlan
proc detached(base: OwnedReport, later: bool): Detached =
  ## All original/current canonical graphs retire on return; the root is selected from the actual producer before response generation.
  let fixture = repeatedLogicalFixture(base)
  var logical = fixture.logical
  if later: logical = executeCurrentLogicalRefresh(namespaceRefreshStages(fixture.logical,
      fixture.next).complete).value
  let root = logical.logicalProducer.currentUpdateState.commitment.root
  let plan = logicalProofPlan()
  let limits = logicalProofLimits()
  let response = executeProofQuery(logicalProofQuery(logical, plan)).value
  var short = limits
  short.wireBytes = ByteLimit(818) # Fixed eighteen-key minimum envelope admits capture; actual global payloads cannot fit this transport budget.
  let producer = logical.logicalProducer
  let selected = producer.currentUpdateView.bestBlock
  let refused = executeProofQuery(captureProofQuery(selected, plan, short).value)
  assert refused.error == ProofQueryError.ViewFailure and refused.viewError ==
      ProofViewError.LimitExceeded
  short = limits
  short.map.perValue = ByteLimit(0)
  let proofRefused = executeProofQuery(captureProofQuery(selected, plan, short).value)
  assert proofRefused.error == ProofQueryError.ProofFailure and proofRefused.proofError ==
      StateProofError.LimitExceeded
  Detached(expected: root, response: response, plan: plan)
proc verify(first, second: Detached) =
  ## Both complete authentications use independent saved expectations; successful old evidence remains old and cannot authorize the later state.
  let limits = logicalProofLimits()
  let oldWire = first.response.bytes(limits.wireBytes).value
  let newWire = second.response.bytes(limits.wireBytes).value
  let old = decodePlannedProofs(oldWire, first.plan, first.expected, limits.view, limits.proof,
      limits.aggregate, limits.wireBytes).value
  let current = decodePlannedProofs(newWire, second.plan, second.expected, limits.view,
      limits.proof, limits.aggregate, limits.wireBytes).value
  assert uint32(old.readGlobalTime.value) == 2 and uint32(current.readGlobalTime.value) == 3
  let oldAsNew = decodePlannedProofs(oldWire, first.plan, second.expected, limits.view,
      limits.proof, limits.aggregate, limits.wireBytes)
  assert oldAsNew.error == ProofViewError.ProofFailure and oldAsNew.proofError ==
      StateProofError.RootMismatch
  let newAsOld = decodePlannedProofs(newWire, second.plan, first.expected, limits.view,
      limits.proof, limits.aggregate, limits.wireBytes)
  assert newAsOld.error == ProofViewError.ProofFailure and newAsOld.proofError ==
      StateProofError.RootMismatch
proc main() {.raises.} =
  ## Independent local fixture activations must expire before either detached response is consumed.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var bytes = newSeq[byte](raw.len)
  for i in 0..<raw.len: bytes[i] = byte(raw[i])
  let base = decodeOwnedReport(bytes, 2).value
  let first = detached(base, false)
  let second = detached(base, true)
  assert array[32, byte](first.expected) != array[32, byte](second.expected)
  assert array[32, byte](first.response.stateRoot) == array[32, byte](first.expected)
  assert array[32, byte](second.response.stateRoot) == array[32, byte](second.expected)
  for i in 0..<25: verify(first, second)
  let before = getOccupiedMem()
  for i in 0..<1000: verify(first, second)
  let finalBytes = getOccupiedMem()
  assert before == finalBytes
  recordArcRelease("state_current_logical_proof_roots", 1000, before, finalBytes)
  echo "state-current-logical-proof-roots: ok"
try:
  main()
except:
  quit(2) # Response claims and unchanged namespace identities never replace independently selected posterior root expectations.
