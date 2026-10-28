# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## The maintained signed rotation at slot12 feeds genuine slot13/14 successors under the exact rotated selected state.
import std/assertions
import ../../src/app/chain as app_chain
import ../../src/chain/genesis as chain_genesis
import ../../src/chain/provider as chain_provider
import ../../src/codec/report_owned as codec_report_owned
import ../../src/state/accumulation_current_update as state_accumulation_current_update
import ../../src/state/accumulation_current_consensus as state_accumulation_current_consensus
import ../../src/state/report_admission as state_report_admission
import ../../src/state/block_transition as state_block_transition
import ../../src/state/block_admission as state_block_admission
import ./state_current_consecutive_context
import ./state_accumulation_current_chain_context
proc currentRotatedSequenceFixture*(base: OwnedReport,
    count: Positive = 3): CurrentConsecutiveFixture =
  ## Rotation signatures/markers are authored by the existing fixture before any root; later bodies stay in that second epoch.
  assert count <= 4
  result = default(CurrentConsecutiveFixture)
  result.seed = currentChainFixture(base, rotated = true)
  var chain = initApplicationChain(genesisView(result.seed.parent)).value
  result.heads.add(chain.chainView.bestBlock.value)
  var ancestors = result.seed.older
  for index in 0..<count:
    let before = chain.chainView.bestBlock.value
    let child = if index == 0: result.seed.source.currentChainAdmission.reportBlockStage.value.value.admitted.admittedBlock else: currentSameEpochBodyChild(
        before, [0'u8, 0, 0, 0, 0, 0, 0])
    let update = phaseCurrentUpdate(chain, child, ancestors, currentConsecutiveLimits())
    assert chain.canInstallPrepared(update)
    chain.installPrepared(update)
    result.children.add(child)
    result.heads.add(chain.chainView.bestBlock.value)
    var next = @[before.header]
    for header in ancestors: next.add(header)
    ancestors = next # Original immutable history is captured before any worker leases exist.
