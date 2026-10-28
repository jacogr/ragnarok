# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "pvm_current_candidate_arc_release"}

## Genuine signed blocks traverse shared admission and current-only execution/state/capture before any canonical publication.
import std/assertions
import std/envvars
import std/syncio
import ../../../src/app/chain as app_chain
import ../../../src/app/candidate as app_candidate
import ../../../src/chain/genesis as chain_genesis
import ../../../src/chain/provider as chain_provider
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/report_owned as codec_report_owned
import ../../../src/codec/block_codec as codec_block_codec
import ../../../src/codec/header as codec_header
import ../../../src/codec/composite as codec_composite
import ../../../src/state/store as state_store
import ../../../src/state/block_admission as state_block_admission
import ../../../src/state/report_admission as state_report_admission
import ../../../src/state/accumulation_current_consensus as state_accumulation_current_consensus
import ../../../src/state/accumulation_current_update as state_accumulation_current_update
import ../../../src/state/accumulation_current_completion as state_accumulation_current_completion
import ../../../src/state/accumulation_current_driver as state_accumulation_current_driver
import ../../support/state_accumulation_current_chain_context
import ../../support/state_accumulation_current_candidate_context
import ../../support/pvm_accumulation_provision
import ../../support/testing_arc_evidence
proc currentLimits(provided: bool): CurrentCandidateLimits =
  ## Real provided preimages use the same explicit capture ceilings as the independently assembled current fixture.
  result = currentCandidateLimits()
  if provided:
    result.completion.execution.initial.guests.provisions = provisionPolicy(items = 2, perBlob = 1, total = 2)
    result.completion.execution.initial.provisions.values = PreimageLimits(items: ElementLimit(2),
        perBlob: ByteLimit(1), totalBlobBytes: ByteLimit(2))
    result.completion.execution.initial.provisions.encodedBytes = ByteLimit(32)
    result.completion.execution.execution.round = result.completion.execution.initial
proc verify(context: CurrentChainFixture, provided: bool) =
  ## One-shot and split preparation produce the independently assembled complete current state and keep the original head private.
  let original = initApplicationChain(context.currentChainSeeded).value
  let bound = context.source.currentChainAdmission.reportBlockStage.value.value.admitted
  let child = bound.admittedBlock
  let limits = currentLimits(provided)
  let prepared = prepareCurrentCandidateReports(original, child, limits)
  assert prepared.error == CurrentCandidateError.None and prepared.value.ready
  assert currentCandidateLookupDemand(prepared.value, []).error == ReportAdmissionError.None
  let outcome = completeCurrentCandidateReports(original, prepared.value, [])
  assert outcome.error == CurrentCandidateError.None
  let update = outcome.value
  let expected = context.source.currentConsensusState.value
  assert array[32, byte](update.currentUpdateState.commitment.root) == array[32, byte](
      expected.commitment.root)
  let immediate = prepareCurrentCandidate(original, child, [], limits)
  assert immediate.error == CurrentCandidateError.None
  assert array[32, byte](immediate.value.currentUpdateState.commitment.root) == array[32, byte](
      expected.commitment.root)
  assert original.canInstallPrepared(update)
  var selected = original
  selected.installPrepared(update)
  let stale = completeCurrentCandidateReports(selected, prepared.value, [])
  assert stale.error == CurrentCandidateError.StateChanged
  assert sameStateSnapshot(original.stateSnapshot.value, context.parent.value.stateSnapshot)
  var tiny = limits
  tiny.headerBytes = ByteLimit(1)
  let capture = prepareCurrentCandidate(original, child, [], tiny)
  assert capture.error == CurrentCandidateError.PreparationFailure
  assert capture.preparationFailure.error == CurrentChainPreparationError.ChainFailure
  tiny = limits
  tiny.completion.execution.execution.entries = ElementLimit(0)
  let execution = prepareCurrentCandidate(original, child, [], tiny)
  assert execution.error == CurrentCandidateError.CompletionFailure
  assert execution.completionFailure.error == CurrentAccumulationCompletionError.SequenceFailure
  tiny = limits
  tiny.queue.items = ElementLimit(0)
  let queued = prepareCurrentCandidate(original, child, [], tiny)
  assert queued.error == CurrentCandidateError.QueueFailure
  let absent = prepareCurrentCandidate(default(ApplicationChain), child, [], limits)
  assert absent.error == CurrentCandidateError.PrefixFailure
  assert absent.prefixFailure.error == ApplicationCandidateError.MissingHead
proc cycle(context: CurrentChainFixture) =
  ## A genuine current candidate's private state, child and original prefix retire without changing the application.
  let owner = initApplicationChain(context.currentChainSeeded).value
  let child = context.source.currentChainAdmission.reportBlockStage.value.value.admitted.admittedBlock
  let prepared = prepareCurrentCandidate(owner, child, [], currentLimits(false))
  assert prepared.error == CurrentCandidateError.None
proc main() {.raises.} =
  ## Signed native fixtures exercise actual admission/current PVM execution with and without preimage effects.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var bytes = newSeq[byte](raw.len)
  for index in 0..<raw.len: bytes[index] = byte(raw[index])
  let base = decodeOwnedReport(bytes, 2).value
  let quiet = currentChainFixture(base, available = true)
  let provided = currentChainFixture(base, available = true, blobs = true)
  verify(quiet, false)
  verify(provided, true)
  let defaulted = completeCurrentCandidateReports(default(ApplicationChain), default(
      PreparedCurrentCandidateReports), [])
  assert defaulted.error == CurrentCandidateError.Uninitialized
  cycle(quiet)
  let before = getOccupiedMem()
  for iteration in 0..<1000: cycle(quiet) # Each complete candidate activation releases every retained original/candidate alias.
  let after = getOccupiedMem()
  assert before == after, "current signed candidate releases"
  recordArcRelease("pvm_current_candidate", 1000, before, after)
  echo "PVM current candidate passed"
  echo "ARC_RELEASE cycles=1000 unchanged"
try:
  main() # Unexpected signature, source or native failure is never passing candidate evidence.
except:
  quit(2)
