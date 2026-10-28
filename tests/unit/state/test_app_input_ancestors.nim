# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Generation-safe input suspension releases raw bytes and resumes the exact prepared signed candidate after context acquisition.
import std/assertions
import std/envvars
import std/syncio
import ../../../src/app/block_input as app_block_input
import ../../../src/app/candidate as app_candidate
import ../../../src/app/chain as app_chain
import ../../../src/chain/genesis as chain_genesis
import ../../../src/chain/provider as chain_provider
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/report_owned as codec_report_owned
import ../../../src/codec/block_codec as codec_block_codec
import ../../../src/codec/header as codec_header
import ../../../src/state/report_anchors as state_report_anchors
import ../../../src/state/accumulation_finalization as state_accumulation_finalization
import ../../../src/state/accumulation_completion as state_accumulation_completion
import ../../../src/state/accumulation_chain as state_accumulation_chain
import ../../../src/state/store as state_store
import ../../support/app_candidate_context
import ../../support/state_accumulation_completion_context
import ../../support/state_report_admission_context as report_context

proc main() {.raises.} =
  ## Actual signed reports require their historical header; no fabricated prefix or finalization certificate is used.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var source = newSeq[byte](raw.len)
  for index, octet in raw: source[index] = byte(octet) # Capture the canonical independent report fixture.
  let base = decodeOwnedReport(source, 2).value
  let context = fixture(base, guarantees = 1)
  var chain = initialized(context)
  let blockOwner = candidateBlock(context)
  var wire = newSeq[byte](blockOwner.blockInfo.value.consumed)
  assert encodeOwnedBlock(blockOwner, wire).error == FrameError.None
  let older = report_context.authored(base).older
  let resources = BlockInputLimits(blockBytes: ByteLimit(wire.len), ancestorBytes: ByteLimit(8192),
    ancestors: ElementLimit(1), discoverAncestors: true)
  var input = default(BlockInput)
  let id = input.begin(chain, ByteLimit(wire.len), [], resources, preparationLimits()).value
  assert input.append(id, wire, true) == BlockInputError.None
  let missing = input.prepare(id, chain)
  assert missing.error == BlockInputError.NeedsAncestors
  assert input.stage == BlockInputStage.AwaitingAncestors
  assert missing.ancestorDemand.missingLookups.value == 1
  assert input.prepare(id, chain).error == BlockInputError.NotReady
  assert input.append(id, [], true) == BlockInputError.Busy
  assert input.resumeAncestors(default(BlockInputId), chain, older) == BlockInputError.StaleInput
  assert input.resumeAncestors(id, chain, [older[0], older[0]]) == BlockInputError.LimitExceeded
  assert input.resumeAncestors(id, chain, [default(OwnedHeader)]) == BlockInputError.InvalidAncestor
  assert input.stage == BlockInputStage.AwaitingAncestors
  assert input.resumeAncestors(id, chain, []) == BlockInputError.None
  let stillMissing = input.prepare(id, chain)
  assert stillMissing.error == BlockInputError.NeedsAncestors # Short context can suspend again without re-decoding or revalidating the original block.
  assert input.resumeAncestors(id, chain, older) == BlockInputError.None
  let complete = input.prepare(id, chain)
  assert complete.error == BlockInputError.None and input.stage == BlockInputStage.Idle
  assert complete.value.finalAccumulationInfo.value.outputs.executions == 2
  assert chain.chainView.retainedCount == 1
  assert chain.applyAccumulation(complete.value, completionLimits().composition).error ==
      ApplicationChainError.None
  assert input.resumeAncestors(id, chain, older) == BlockInputError.StaleInput
  assert input.prepare(id, chain).error == BlockInputError.StaleInput
  echo "input-ancestors: ok"
try:
  main() # Fixture IO must fail rather than produce the expected line.
except:
  quit(2)
