# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Genuine current composed fixtures and exact source parameters support state/view and durable-publication witnesses.
import std/assertions
import ../../src/chain/[parameters, genesis, provider]
import ../../src/codec/[bounded, header, composite, report_owned, state_trie]
import ../../src/state/[accumulation_current_consensus, accumulation_consensus,
  accumulation_current_authorization, accumulation_authorization, accumulation_current_preimages,
  accumulation_preimages, accumulation_current_activity, accumulation_activity,
  accumulation_current_validators, accumulation_current_recent, accumulation_current_ready,
  accumulation_current_finalization, accumulation_current_accounts, accumulation_current_statistics,
  accumulation_current_driver, accumulation_current_sequence, accumulation_current_round,
  accumulation_block_guests, accumulation_round, accumulation_queue, report_admission,
  block_transition, block_admission, preimages, store]
import ./[accumulation_current_activity_context, accumulation_current_round_context]
type CurrentChainFixture* = object ## Actual current authority retains its structurally captured exact parent and independently authored parent keys.
  source*: PreparedCurrentAccumulationConsensus
  parent*: BlockSnapshotResult
  entries*: seq[StateEntry]
proc currentChainSettings*(epoch = 12'u8, alteredPrice = false): Parameters =
  ## Use the exact frozen execution tuple; mismatch probes alter only one explicit epoch or deposit field.
  var wire = currentRoundParameters().encodeParameters
  wire[30] = epoch
  if alteredPrice: wire[8] = 1 # depositPerByte differs while all core/epoch/validator domains remain unchanged.
  decodeParameters(wire).value
proc currentChainBytes*(header: OwnedHeader): seq[byte] =
  ## Copy exact sealed bytes only after genuine owner metadata selects their complete extent.
  result = newSeq[byte](header.headerInfo.value.consumed)
  assert header.encodeOwnedHeader(result).error == HeaderError.None
proc currentChainAdmission*(source: PreparedCurrentAccumulationConsensus): AdmittedReports =
  ## Retain the source's exact admission; this test helper grants no synthetic completion authority.
  source.currentConsensusSource.value.currentAuthorizationSource.value.currentPreimagesSource.value.currentActivitySource.value.currentValidatorsSource.value.currentRecentSource.value.currentReadySource.value.currentFinalizationAccounts.value.currentAccountsSource.value.currentStatisticsSource.value.completedSequenceSource.value.currentSequenceInitial.value.currentRoundGuests.value.guestRound.value.roundBlockQueue.value.accumulationAdmission.value
proc currentChainParent*(source: PreparedCurrentAccumulationConsensus): StateStoreSnapshot =
  ## Cached original-parent preimage admission retains exact identity even for an empty extrinsic.
  source.currentConsensusSource.value.currentAuthorizationSource.value.currentPreimagesSource.value.currentActivityPreimages.value.preimagePrior.value
proc currentChainFixture*(base: OwnedReport, uses = 0, available = false, blobs = false,
    disputed = false, ticket = false, rotated = false, writes = 1000'u64): CurrentChainFixture =
  ## Every signature, current guest/phase, statistic and private map comes from real production constructors.
  let authored = currentActivityFixture(base, guarantees = uses, available = available,
    blobs = blobs,
    provided = blobs, withDispute = disputed, withTicket = ticket, shiftPending = rotated,
    slot = (if rotated: 12'u32 else: 2'u32), storeWrites = writes)
  let activity = prepareCurrentAccumulationActivity(authored.source, AccumulationActivityConfig(
    componentBytes: ByteLimit(1024), preimages: PreimageLimits(items: ElementLimit(3),
      perBlob: ByteLimit(3), totalBlobBytes: ByteLimit(4)), incoming: ElementLimit(2),
    available: ElementLimit(1), digests: ElementLimit(2), assurances: ElementLimit(5),
    provisions: ElementLimit(2), accumulation: ElementLimit(2), services: ElementLimit(2),
    activityBytes: ByteLimit(4096))).value
  let lookup = prepareCurrentAccumulationPreimages(activity, AccumulationPreimageLimits(
    items: ElementLimit(3), bytes: ByteLimit(4))).value
  let pools = prepareCurrentAccumulationAuthorization(lookup, AccumulationAuthorizationLimits(
    guarantees: ElementLimit(2), inputHashes: ElementLimit(160), inputBytes: ByteLimit(5120),
    outputHashes: ElementLimit(16), outputBytes: ByteLimit(514))).value
  let source = prepareCurrentAccumulationConsensus(pools, AccumulationConsensusLimits(
    chapterBytes: ByteLimit(10000), totalBytes: ByteLimit(50000))).value
  let binding = source.currentChainAdmission.reportBlockStage.value.value.admitted
  let captured = captureBlockSnapshot(currentChainBytes(binding.admittedParent),
    source.currentChainParent, currentChainSettings())
  assert captured.error == GenesisError.None, "exact source parameter tuple captures genuine parent"
  CurrentChainFixture(source: source, parent: captured, entries: authored.entries)
proc currentChainSeeded*(context: CurrentChainFixture): ChainView =
  ## Explicit finality stays on the retained parent while its child becomes the selected head.
  genesisView(context.parent).finalizeView(context.parent.value.blockHash).value
