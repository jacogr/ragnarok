# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Actual guest provides span current blocks under explicit capture/union policy, before a conflicting mixed delivery body.
import std/assertions
import ../../src/app/[chain, candidate]
import ../../src/chain/[genesis, provider]
import ../../src/codec/[block_codec, report_owned, bounded, composite]
import ../../src/state/accumulation_current_update
import ./[current_consecutive_context, current_preimage_sequence_context,
  accumulation_activity_context, accumulation_execution_context, pvm_accumulation_provision]

type CurrentProvisionSequenceFixture* = object ## Genuine expected maps and a fresh mixed body retain exact original immutable owners.
  sequence*: CurrentConsecutiveFixture
  mixed*: OwnedBlock

proc currentProvisionSequenceLimits*(): CurrentCandidateLimits =
  ## Permit the actual two one-byte guest provisions explicitly; the ordinary zero-union defaults remain unchanged.
  result = currentConsecutiveLimits()
  result.completion.execution.initial.guests.provisions = provisionPolicy(items = 2, perBlob = 1, total = 2)
  result.completion.execution.initial.provisions.values = PreimageLimits(items: ElementLimit(2),
    perBlob: ByteLimit(1), totalBlobBytes: ByteLimit(2))
  result.completion.execution.initial.provisions.encodedBytes = ByteLimit(32)
  result.completion.execution.execution.round = result.completion.execution.initial

proc currentProvisionSequenceFixture*(base: OwnedReport): CurrentProvisionSequenceFixture =
  ## Real providing programs run on both empty children; no extrinsic supplies those values before the rejected mixed body.
  result = default(CurrentProvisionSequenceFixture)
  let limits = currentProvisionSequenceLimits()
  let authored = executionFixture(base, activityOptions(blobs = true, provided = true))
  result.sequence.seed = currentExecutionSeed(authored, limits)
  var chain = initApplicationChain(genesisView(result.sequence.seed.parent)).value
  result.sequence.heads.add(chain.chainView.bestBlock.value)
  var ancestors = result.sequence.seed.older
  for index in 0..1:
    let before = chain.chainView.bestBlock.value
    let child = currentEmptyChild(before)
    let update = phaseCurrentUpdate(chain, child, ancestors, limits)
    assert chain.canInstallPrepared(update)
    chain.installPrepared(update)
    result.sequence.children.add(child)
    result.sequence.heads.add(chain.chainView.bestBlock.value)
    var next = @[before.header]
    for header in ancestors: next.add(header)
    ancestors = next # Every owner/copy is stable before any later native Services job starts.
  result.mixed = currentBodyChild(chain.chainView.bestBlock.value, currentFixtureBody(
      result.sequence.seed))
