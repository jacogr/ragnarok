# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Genuine slot3 report guarantees follow an empty slot2 child and retain exact original lookup owners.
import std/assertions
import ../../src/app/chain
import ../../src/chain/[genesis, provider]
import ../../src/codec/[report_owned, header]
import ../../src/state/accumulation_current_update
import ./[current_consecutive_context, current_preimage_sequence_context,
  accumulation_activity_context, accumulation_execution_context]

type CurrentGuaranteeSequenceFixture* = object ## Reports and signatures are authored before current transitions; no lookup-completion authority is fabricated.
  sequence*: CurrentConsecutiveFixture
  ancestors*: seq[OwnedHeader]

proc currentGuaranteeSequenceFixture*(base: OwnedReport): CurrentGuaranteeSequenceFixture =
  ## Existing signed options author slot3 guarantees; every actual successor is independently resealed against its immediate predecessor.
  result = default(CurrentGuaranteeSequenceFixture)
  let limits = currentConsecutiveLimits()
  let authored = executionFixture(base, activityOptions(guarantees = 2, slot = 3))
  result.sequence.seed = currentExecutionSeed(authored, limits)
  let body = currentFixtureBody(result.sequence.seed)
  var chain = initApplicationChain(genesisView(result.sequence.seed.parent)).value
  result.sequence.heads.add(chain.chainView.bestBlock.value)
  var ancestors = result.sequence.seed.older
  for index in 0..1:
    let before = chain.chainView.bestBlock.value
    if index == 1: result.ancestors = ancestors # Exact parent-inclusive original lookup context belongs to this second body.
    let child = if index == 0: currentEmptyChild(before) else: currentBodyChild(before, body)
    let update = phaseCurrentUpdate(chain, child, ancestors, limits)
    assert chain.canInstallPrepared(update)
    chain.installPrepared(update)
    result.sequence.children.add(child)
    result.sequence.heads.add(chain.chainView.bestBlock.value)
    var next = @[before.header]
    for header in ancestors: next.add(header)
    ancestors = next # Retain immutable original headers only while the host owns every graph.
