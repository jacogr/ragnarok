# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "pvm_current_completion_arc_release"}

## The complete current builder matches existing phase witnesses and preserves every actual failure without publication.
import std/assertions
import std/envvars
import std/syncio
import ../../../src/state/accumulation_current_statistics as state_accumulation_current_statistics
import ../../../src/state/accumulation_current_accounts as state_accumulation_current_accounts
import ../../../src/state/accumulation_current_finalization as state_accumulation_current_finalization
import ../../../src/state/accumulation_current_ready as state_accumulation_current_ready
import ../../../src/state/accumulation_current_recent as state_accumulation_current_recent
import ../../../src/state/accumulation_current_validators as state_accumulation_current_validators
import ../../../src/state/accumulation_current_activity as state_accumulation_current_activity
import ../../../src/state/accumulation_current_preimages as state_accumulation_current_preimages
import ../../../src/state/accumulation_current_authorization as state_accumulation_current_authorization
import ../../../src/state/accumulation_current_consensus as state_accumulation_current_consensus
import ../../../src/state/accumulation_current_completion as state_accumulation_current_completion
import ../../../src/state/accumulation_current_driver as state_accumulation_current_driver
import ../../../src/state/accumulation_current_sequence as state_accumulation_current_sequence
import ../../../src/state/accumulation_current_round as state_accumulation_current_round
import ../../../src/state/accumulation_accounts as state_accumulation_accounts
import ../../../src/state/accumulation_ready as state_accumulation_ready
import ../../../src/state/accumulation_recent as state_accumulation_recent
import ../../../src/state/accumulation_validators as state_accumulation_validators
import ../../../src/state/accumulation_activity as state_accumulation_activity
import ../../../src/state/accumulation_preimages as state_accumulation_preimages
import ../../../src/state/accumulation_authorization as state_accumulation_authorization
import ../../../src/state/accumulation_consensus as state_accumulation_consensus
import ../../../src/state/accumulation_provisions as state_accumulation_provisions
import ../../../src/state/preimages as state_preimages
import ../../../src/state/accumulation_block_guests as state_accumulation_block_guests
import ../../../src/state/store as state_store
import ../../../src/state/accumulation_round as state_accumulation_round
import ../../../src/state/accumulation_queue as state_accumulation_queue
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/composite as codec_composite
import ../../../src/codec/report_owned as codec_report_owned
import ../../support/state_accumulation_current_chain_context
import ../../support/state_accumulation_current_completion_context
import ../../support/state_accumulation_current_round_context
import ../../support/pvm_accumulation_provision
import ../../support/testing_arc_evidence
proc terminal(context: CurrentChainFixture): CompletedCurrentAccumulationSequence =
  ## Retain the genuine terminal input from the independently assembled current witness.
  context.source.currentConsensusSource.value.currentAuthorizationSource.value.currentPreimagesSource.value.currentActivitySource.value.currentValidatorsSource.value.currentRecentSource.value.currentReadySource.value.currentFinalizationAccounts.value.currentAccountsSource.value.currentStatisticsSource.value
proc verify(context: CurrentChainFixture) =
  ## One builder must produce the same whole-map root as the existing manually assembled current state path.
  let completed = context.terminal
  let expected = context.source.currentConsensusState.value
  let before = completed.completedSequenceState.value
  let outcome = prepareCurrentAccumulationComposition(completed, currentCompositionLimits())
  assert outcome.error == CurrentAccumulationCompletionError.None
  let actual = outcome.value.currentConsensusState.value
  assert array[32, byte](actual.commitment.root) == array[32, byte](expected.commitment.root)
  assert actual.commitment.entries == expected.commitment.entries
  assert sameStateSnapshot(before, completed.completedSequenceState.value)
  var statisticsLimits = currentCompositionLimits()
  statisticsLimits.statistics = default(CurrentAccumulationStatisticsLimits)
  let statistics = prepareCurrentAccumulationComposition(completed, statisticsLimits)
  assert statistics.error == CurrentAccumulationCompletionError.StatisticsFailure
  assert statistics.statisticsFailure.error != CurrentAccumulationStatisticsError.None
  var accountsLimits = currentCompositionLimits()
  accountsLimits.accounts = default(AccumulationAccountConfig)
  let accounts = prepareCurrentAccumulationComposition(completed, accountsLimits)
  assert accounts.error == CurrentAccumulationCompletionError.AccountsFailure
  assert accounts.accountsFailure.error != CurrentAccumulationAccountError.None
  var finalizationLimits = currentCompositionLimits()
  finalizationLimits.finalization = default(CurrentAccumulationFinalizationConfig)
  let finalization = prepareCurrentAccumulationComposition(completed, finalizationLimits)
  assert finalization.error == CurrentAccumulationCompletionError.FinalizationFailure
  assert finalization.finalizationFailure.error != CurrentAccumulationFinalizationError.None
  var readyLimits = currentCompositionLimits()
  readyLimits.ready = default(AccumulationReadyConfig)
  let ready = prepareCurrentAccumulationComposition(completed, readyLimits)
  assert ready.error == CurrentAccumulationCompletionError.ReadyFailure
  assert ready.readyFailure.error != CurrentAccumulationReadyError.None
  var recentLimits = currentCompositionLimits()
  recentLimits.recent = default(AccumulationRecentConfig)
  let recent = prepareCurrentAccumulationComposition(completed, recentLimits)
  assert recent.error == CurrentAccumulationCompletionError.RecentFailure
  assert recent.recentFailure.error != CurrentAccumulationRecentError.None
  var validatorsLimits = currentCompositionLimits()
  validatorsLimits.validators = default(AccumulationValidatorsConfig)
  let validators = prepareCurrentAccumulationComposition(completed, validatorsLimits)
  assert validators.error == CurrentAccumulationCompletionError.ValidatorsFailure
  assert validators.validatorsFailure.error != CurrentAccumulationValidatorsError.None
  var activityLimits = currentCompositionLimits()
  activityLimits.activity = default(AccumulationActivityConfig)
  let activity = prepareCurrentAccumulationComposition(completed, activityLimits)
  assert activity.error == CurrentAccumulationCompletionError.ActivityFailure
  assert activity.activityFailure.error != CurrentAccumulationActivityError.None
  var preimagesLimits = currentCompositionLimits()
  preimagesLimits.preimages = default(AccumulationPreimageLimits)
  let preimages = prepareCurrentAccumulationComposition(completed, preimagesLimits)
  assert preimages.error == CurrentAccumulationCompletionError.PreimagesFailure
  assert preimages.preimagesFailure.error != CurrentAccumulationPreimageError.None
  var authorizationLimits = currentCompositionLimits()
  authorizationLimits.authorization = default(AccumulationAuthorizationLimits)
  let authorization = prepareCurrentAccumulationComposition(completed, authorizationLimits)
  assert authorization.error == CurrentAccumulationCompletionError.AuthorizationFailure
  assert authorization.authorizationFailure.error != CurrentAccumulationAuthorizationError.None
  var consensusLimits = currentCompositionLimits()
  consensusLimits.consensus = default(AccumulationConsensusLimits)
  let consensus = prepareCurrentAccumulationComposition(completed, consensusLimits)
  assert consensus.error == CurrentAccumulationCompletionError.ConsensusFailure
  assert consensus.consensusFailure.error != CurrentAccumulationConsensusError.None
proc cycle(context: CurrentChainFixture) =
  ## All state-only candidate handles retire in this activation without modifying the retained terminal input.
  let composed = prepareCurrentAccumulationComposition(context.terminal, currentCompositionLimits())
  assert composed.error == CurrentAccumulationCompletionError.None
proc main() {.raises.} =
  ## Signed report inputs drive genuine current execution and the independently assembled expected state.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var bytes = newSeq[byte](raw.len)
  for index in 0..<raw.len: bytes[index] = byte(raw[index])
  let base = decodeOwnedReport(bytes, 2).value
  let quiet = currentChainFixture(base)
  let rich = currentChainFixture(base, uses = 2, available = true, blobs = true)
  verify(rich)
  let quietResult = prepareCurrentAccumulationComposition(quiet.terminal, currentCompositionLimits())
  assert quietResult.error == CurrentAccumulationCompletionError.None
  let invalid = prepareCurrentAccumulationComposition(default(CompletedCurrentAccumulationSequence),
      currentCompositionLimits())
  assert invalid.error == CurrentAccumulationCompletionError.InvalidSource
  let noRound = runCurrentAccumulationCompletion(default(BlockAccumulationRound),
      currentRoundParameters(), currentCompletionLimits())
  assert noRound.error == CurrentAccumulationCompletionError.SequenceFailure
  assert noRound.sequenceFailure.error != CurrentSequenceDriverError.None
  # A fresh runner uses the original genuine round and frozen profile from the retained initial sequence fact.
  let initial = rich.terminal.completedSequenceSource.value.currentSequenceInitial.value
  let admitted = initial.currentRoundGuests.value.guestRound.value
  var limits = currentCompletionLimits()
  limits.execution.initial.guests.provisions = provisionPolicy(items = 2, perBlob = 1, total = 2)
  limits.execution.initial.provisions.values = PreimageLimits(items: ElementLimit(2),
      perBlob: ByteLimit(1), totalBlobBytes: ByteLimit(2))
  limits.execution.initial.provisions.encodedBytes = ByteLimit(32)
  limits.execution.execution.round = limits.execution.initial
  let replayed = runCurrentAccumulationCompletion(admitted, currentRoundParameters(), limits)
  assert replayed.error == CurrentAccumulationCompletionError.None
  let replayedState = replayed.value.currentConsensusState.value
  let expectedState = rich.source.currentConsensusState.value
  assert array[32, byte](replayedState.commitment.root) == array[32, byte](
      expectedState.commitment.root)
  cycle(rich)
  let before = getOccupiedMem()
  for iteration in 0..<1000: cycle(rich) # Immutable source ownership remains acyclic through every fresh complete composition.
  let after = getOccupiedMem()
  assert before == after, "current completion releases"
  recordArcRelease("pvm_current_completion", 1000, before, after)
  echo "PVM current completion passed"
  echo "ARC_RELEASE cycles=1000 unchanged"
try:
  main() # Any fixture/native failure prevents a passing completion result.
except:
  quit(2)
