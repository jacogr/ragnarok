# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## The maintained signed rotation at slot12 feeds genuine slot13/14 successors under the exact rotated selected state.
import std/assertions
import ../../src/app/chain
import ../../src/chain/[genesis, provider]
import ../../src/codec/report_owned
import ../../src/state/accumulation/current/[update as accumulation_current_update,
    consensus as accumulation_current_consensus]
import ../../src/state/report/admission as report_admission
import "../../src/state/block/transition" as block_transition
import "../../src/state/block/admission" as block_admission
import ./[current_consecutive_context, accumulation_current_chain_context]
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
