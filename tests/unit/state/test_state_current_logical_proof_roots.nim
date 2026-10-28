# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Detached authentic successor responses survive source retirement but old/new evidence cannot cross independently retained actual roots.
# @@Verification={"arc":"state_current_logical_proof_roots_arc_release"}
import std/assertions
import std/envvars
import std/syncio
import ../../support/state_current_repeated_logical_context
import ../../support/state_current_namespace_refresh_context
import ../../support/state_current_logical_proof_context
import ../../support/testing_arc_evidence
import ../../../src/state/current_logical_refresh as state_current_logical_refresh
import ../../../src/state/current_logical as state_current_logical
import ../../../src/state/accumulation_current_update as state_accumulation_current_update
import ../../../src/state/proof_plan as state_proof_plan
import ../../../src/state/planned_proof as state_planned_proof
import ../../../src/state/proof_view as state_proof_view
import ../../../src/state/proof_global as state_proof_global
import ../../../src/state/trie_proof as state_trie_proof
import ../../../src/state/store as state_store
import ../../../src/chain/provider as chain_provider
import ../../../src/chain/genesis as chain_genesis
import ../../../src/app/proof_query as app_proof_query
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/report_owned as codec_report_owned
import ../../../src/codec/state_layout as codec_state_layout
import ../../../src/codec/state_trie as codec_state_trie
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
