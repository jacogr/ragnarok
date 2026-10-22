# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bounded genuine current chains retain independently authored wires and explicit phase-composed expected maps.
import std/assertions
import ../../src/app/[chain, candidate]
import ../../src/chain/[genesis, provider]
import ../../src/codec/[bounded, header, block_codec, report_owned, state_layout, state_safrole]
import ../../src/state/[store, block_transition, report_admission, accumulation_queue,
  accumulation_round, accumulation_current_completion, accumulation_current_update]
import ../../src/crypto/extrinsic_commitment
import ../../src/bandersnatch/bandersnatch
import ./[accumulation_current_chain_context, accumulation_current_candidate_context]

type CurrentConsecutiveFixture* = object ## Test-owned snapshots contain real completion authority, never fabricated tagged certificates.
  seed*: CurrentChainFixture
  children*: seq[OwnedBlock]
  heads*: seq[BlockSnapshot]

proc currentConsecutiveLimits*(): CurrentCandidateLimits =
  ## Explicitly permit up to four statistics rows without changing existing fixture defaults.
  result = currentCandidateLimits()
  result.completion.composition.validators.services = ElementLimit(4)

proc transcript(domain: string, seed: array[32, byte]): seq[byte] =
  ## Signing transcripts keep exact maintained domain octets with one complete fixed entropy word.
  result = newSeq[byte](domain.len+32)
  for index, octet in domain: result[index] = byte(octet)
  for index, octet in seed: result[domain.len+index] = octet

proc currentEmptyChild*(parent: BlockSnapshot): OwnedBlock =
  ## Derive an ordinary child from the actual parent; this authored fixture deliberately stops before an epoch crossing.
  assert uint32(parent.slot) < high(uint32)
  let slot = uint32(parent.slot)+1
  assert uint64(slot) < uint64(parent.epochSlots), "ordinary first-epoch fixture only"
  let limits = currentConsecutiveLimits()
  let frame = limits.reporting.admission.frame
  let headerConfig = limits.reporting.reports.ancestors.header
  let body = @[0'u8, 0, 0, 0, 0, 0, 0]
  let extrinsic = decodeExtrinsic(body, frame)
  assert extrinsic.error == FrameError.None and extrinsic.value.consumed == body.len
  let entropy = decodeStateEntropy(parent.stateSnapshot.lookup(chapterKey(StateChapter(
      6))).value.bytes)
  assert entropy.error == StateComponentError.None
  var scalar = default(array[32, byte])
  scalar[0] = 1
  let key = importScalar(scalar).value
  let context = transcript("jam_fallback_seal", array[32, byte](entropy.value.value[3]))
  let provisional = sign(key, context, []).value
  let output = verify(publicKey(key).value, provisional, context, []).value
  var child = default(header.Header)
  child.unsigned.epoch = absentEpoch()
  child.unsigned.winners = absentWinners()
  child.unsigned.parent = HeaderParent(array[32, byte](parent.blockHash))
  child.unsigned.priorState = PriorStateRoot(array[32, byte](parent.stateSnapshot.commitment.root))
  child.unsigned.extrinsics = ExtrinsicRoot(array[32, byte](extrinsicCommitment(
      extrinsic.value.owner, frame.maxBytes).value))
  child.unsigned.slot = HeaderSlot(slot)
  child.unsigned.entropyProof = HeaderEntropyProof(array[96, byte](sign(key, transcript(
      "jam_entropy", array[32, byte](output)), []).value))
  var unsigned = newSeq[byte](100000)
  let unsignedSize = encodeUnsignedHeader(child.unsigned, headerConfig, unsigned).value
  unsigned.setLen(unsignedSize)
  child.seal = HeaderSeal(array[96, byte](sign(key, context, unsigned).value))
  var wire = newSeq[byte](100000)
  let size = encodeHeader(child, headerConfig, wire).value
  wire.setLen(size)
  for octet in body: wire.add(octet) # Seven exact empty extrinsics follow the fully sealed header.
  let decoded = decodeBlock(wire, frame)
  assert decoded.error == FrameError.None and decoded.value.consumed == wire.len
  decoded.value.owner

proc phaseCurrentUpdate*(chain: ApplicationChain, child: OwnedBlock,
    ancestors: openArray[OwnedHeader], limits: CurrentCandidateLimits): PreparedCurrentChainUpdate =
  ## Individually invoke genuine phase constructors without using the candidate wrapper that consumer tests exercise.
  let parent = chain.chainView.bestBlock.value
  var state = forkStateStore(chain.stateSnapshot.value).value
  let policy = limits.reporting
  let staged = advanceBlockState(state, child, parent.header, policy.admission, policy.disputes,
      policy.safrole, policy.availability)
  assert staged.error == BlockTransitionError.None, "current reference block admission"
  let prefix = prepareBlockReports(staged, policy.reports)
  assert prefix.error == ReportAdmissionError.None
  let reports = completeBlockReports(prefix.value, ancestors)
  assert reports.error == ReportAdmissionError.None
  let queue = planBlockAccumulationQueue(reports.value, limits.queue)
  assert queue.error == AccumulationQueueError.None
  let round = planBlockInitialAccumulation(queue.value, limits.round)
  assert round.error == AccumulationRoundError.None
  let source = runCurrentAccumulationCompletion(round.value, parent.chainParameters,
      limits.completion)
  assert source.error == CurrentAccumulationCompletionError.None, "current reference completion"
  let update = chain.prepareAccumulation(source.value, limits.headerBytes)
  assert update.error == CurrentChainPreparationError.None
  update.value

proc currentConsecutiveFixture*(base: OwnedReport, count: Positive = 3): CurrentConsecutiveFixture =
  ## Finite ordinary chains retain exact parent maps and original lookup context before any later worker/socket ownership.
  assert count <= 4
  result = default(CurrentConsecutiveFixture)
  result.seed = currentChainFixture(base, available = true)
  var chain = initApplicationChain(genesisView(result.seed.parent)).value
  result.heads.add(chain.chainView.bestBlock.value)
  var ancestors = result.seed.older
  let limits = currentConsecutiveLimits()
  for index in 0..<count:
    let before = chain.chainView.bestBlock.value
    let child = if index == 0: result.seed.source.currentChainAdmission.reportBlockStage.value.value.admitted.admittedBlock else: currentEmptyChild(before)
    let update = phaseCurrentUpdate(chain, child, ancestors, limits)
    assert chain.canInstallPrepared(update)
    chain.installPrepared(update)
    result.children.add(child)
    result.heads.add(chain.chainView.bestBlock.value)
    var next = @[before.header]
    for header in ancestors: next.add(header)
    ancestors = next # Replacement happens synchronously without any canonical worker lease.
