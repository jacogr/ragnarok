# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Genuine current preimage bodies follow an empty predecessor, with a separately sealed already-delivered repetition.
import std/assertions
import ../../src/app/chain as app_chain
import ../../src/app/candidate as app_candidate
import ../../src/chain/genesis as chain_genesis
import ../../src/chain/provider as chain_provider
import ../../src/codec/block_codec as codec_block_codec
import ../../src/codec/report_owned as codec_report_owned
import ../../src/state/accumulation_current_completion as state_accumulation_current_completion
import ../../src/state/accumulation_current_update as state_accumulation_current_update
import ../../src/state/report_admission as state_report_admission
import ../../src/state/block_admission as state_block_admission
import ./state_current_consecutive_context
import ./state_accumulation_current_chain_context
import ./state_accumulation_execution_context
import ./state_accumulation_activity_context
import ./state_accumulation_current_round_context

type CurrentPreimageSequenceFixture* = object ## Expected full maps are phase-composed; wires and fixed namespace observations are authored separately.
  sequence*: CurrentConsecutiveFixture
  repeated*: OwnedBlock

proc currentExecutionSeed*(authored: ExecutionFixture,
    limits: CurrentCandidateLimits): CurrentChainFixture =
  ## Complete only a genuine configured execution round, then retain its exact original signed parent and full parameter tuple.
  let completed = runCurrentAccumulationCompletion(authored.round, currentRoundParameters(),
    limits.completion)
  assert completed.error == CurrentAccumulationCompletionError.None, "real configured execution seed completion"
  let source = completed.value
  let admitted = source.currentChainAdmission.reportBlockStage.value.value.admitted
  let parent = captureBlockSnapshot(currentChainBytes(admitted.admittedParent),
    source.currentChainParent, currentChainSettings())
  assert parent.error == GenesisError.None
  CurrentChainFixture(source: source, parent: parent, entries: authored.entries,
      older: authored.older)

proc currentFixtureBody*(seed: CurrentChainFixture): seq[byte] =
  ## Copy only the exact already-admitted extrinsic suffix, retaining independent header sealing for every successor.
  let child = seed.source.currentChainAdmission.reportBlockStage.value.value.admitted.admittedBlock
  let info = child.blockInfo.value
  assert info.consumed <= 100000 and info.headerBytes <= info.consumed
  var wire = newSeq[byte](info.consumed)
  assert child.encodeOwnedBlock(wire).error == FrameError.None
  result = newSeq[byte](info.extrinsicBytes)
  for index in 0..<result.len:
    result[index] = wire[info.headerBytes+index] # Checked component extents are the sole source of byte offsets.

proc currentPreimageSequenceFixture*(base: OwnedReport): CurrentPreimageSequenceFixture =
  ## Real constructors and exact original ancestry qualify each accepted map; the repeated body never receives a completion certificate.
  result = default(CurrentPreimageSequenceFixture)
  let authored = executionFixture(base, activityOptions(blobs = true, provided = false))
  result.sequence.seed = currentExecutionSeed(authored, currentConsecutiveLimits())
  let body = currentFixtureBody(result.sequence.seed)
  var chain = initApplicationChain(genesisView(result.sequence.seed.parent)).value
  result.sequence.heads.add(chain.chainView.bestBlock.value)
  var ancestors = result.sequence.seed.older
  for index in 0..1:
    let before = chain.chainView.bestBlock.value
    let child = if index == 0: currentEmptyChild(before) else: currentBodyChild(before, body)
    let update = phaseCurrentUpdate(chain, child, ancestors, currentConsecutiveLimits())
    assert chain.canInstallPrepared(update)
    chain.installPrepared(update)
    result.sequence.children.add(child)
    result.sequence.heads.add(chain.chainView.bestBlock.value)
    var next = @[before.header]
    for header in ancestors: next.add(header)
    ancestors = next # Every original lookup owner is retained before any later managed-worker borrow.
  result.repeated = currentBodyChild(chain.chainView.bestBlock.value, body)
