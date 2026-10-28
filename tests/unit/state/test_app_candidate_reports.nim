# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Genuine signed guaranteed reports can suspend before guest execution, discover missing context and complete against the exact parent.
import std/assertions
import std/envvars
import std/syncio
import ../../../src/app/candidate as app_candidate
import ../../../src/app/chain as app_chain
import ../../../src/chain/genesis as chain_genesis
import ../../../src/chain/provider as chain_provider
import ../../../src/codec/report_owned as codec_report_owned
import ../../../src/codec/header as codec_header
import ../../../src/state/report_admission as state_report_admission
import ../../../src/state/report_anchors as state_report_anchors
import ../../../src/state/accumulation_completion as state_accumulation_completion
import ../../../src/state/accumulation_finalization as state_accumulation_finalization
import ../../../src/state/accumulation_chain as state_accumulation_chain
import ../../../src/state/store as state_store
import ../../support/app_candidate_context
import ../../support/state_accumulation_completion_context
import ../../support/state_report_admission_context as report_context

proc main() {.raises.} =
  ## Full production stages and genuine guest output provide both prefix and finalization positive controls.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var wire = newSeq[byte](raw.len)
  for index, octet in raw: wire[index] = byte(octet) # The source fixture is decoded once under its explicit profile.
  let base = decodeOwnedReport(wire, 2).value
  let context = fixture(base, guarantees = 1)
  var chain = initialized(context)
  let original = chain.stateSnapshot.value
  let child = candidateBlock(context)
  let older = @[report_context.authored(base).older[0]]
  let prepared = prepareCandidateReports(chain, child, preparationLimits())
  assert prepared.error == ApplicationCandidateError.None
  assert sameStateSnapshot(original, chain.stateSnapshot.value)
  let missing = prepared.value.candidateLookupDemand([])
  assert missing.error == ReportAdmissionError.None and missing.value.missingLookups.value == 1
  let satisfied = prepared.value.candidateLookupDemand(older)
  assert satisfied.error == ReportAdmissionError.None and satisfied.value.missingLookups.value == 0
  let refused = completeCandidateReports(chain, prepared.value, [])
  assert refused.error == ApplicationCandidateError.ReportFailure
  assert refused.reportFailure.anchorError == ReportAnchorError.MissingLookupAnchor
  let actual = completeCandidateReports(chain, prepared.value, older)
  assert actual.error == ApplicationCandidateError.None
  let expected = prepareCandidate(chain, child, older, preparationLimits())
  assert expected.error == ApplicationCandidateError.None
  assert array[32, byte](actual.value.finalAccumulationState.value.commitment.root) ==
    array[32, byte](expected.value.finalAccumulationState.value.commitment.root)
  assert actual.value.finalAccumulationInfo.value.outputs.executions == 2
  assert chain.chainView.retainedCount == 1
  assert chain.applyAccumulation(actual.value, completionLimits().composition).error ==
      ApplicationChainError.None
  assert completeCandidateReports(chain, prepared.value, older).error ==
      ApplicationCandidateError.StateChanged
  assert default(PreparedCandidateReports).candidateLookupDemand([]).error ==
      ReportAdmissionError.InvalidTransition
  assert completeCandidateReports(chain, default(PreparedCandidateReports), []).error ==
      ApplicationCandidateError.Uninitialized
  let failed = prepareCandidateReports(default(ApplicationChain), child, preparationLimits())
  assert failed.error == ApplicationCandidateError.MissingHead and failed.failure.error ==
      ApplicationCandidateError.MissingHead
  let uninitialized = CandidateReportPreparation()
  assert uninitialized.error == ApplicationCandidateError.Uninitialized
  echo "candidate-reports: ok"
try:
  main() # Missing fixture input must fail the native runner.
except:
  quit(2) # Fixture IO refusal cannot produce the expected success output.
