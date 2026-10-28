# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Genuine slot3 report guarantees follow an empty slot2 child and retain exact original lookup owners.
import std/assertions
import ../../src/app/chain as app_chain
import ../../src/chain/genesis as chain_genesis
import ../../src/chain/provider as chain_provider
import ../../src/codec/report_owned as codec_report_owned
import ../../src/codec/header as codec_header
import ../../src/state/accumulation_current_update as state_accumulation_current_update
import ./state_current_consecutive_context
import ./state_current_preimage_sequence_context
import ./state_accumulation_activity_context
import ./state_accumulation_execution_context

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
