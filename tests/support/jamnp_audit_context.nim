# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Genuinely computed, assured, accumulated and published successor state retains its original admitted body for audit-context qualification; no pending report or availability vote is fabricated.
import std/assertions
import ../../src/jamnp-s/[audit_context]
import ../../src/codec/[bounded, block_codec]
import ../../src/codec/state/[layout, safrole]
import ../../src/chain/[genesis, provider]
import ../../src/state/computed/assurances
import "../../src/state/block/admission"
import ../../src/state/assured/[chain, composition, execution, queue]
import ./[pvm_assured_chain, pvm_computed_assurances]
type AuditContextFixture* = object ## Test-owned retained views contain actual complete publication, real body and independent predecessor authority.
  view*, prior*: ChainView
  blockHash*: genesis.BlockHash
  candidate*: OwnedBlock
proc auditContextFixture*(votes = 7): AuditContextFixture =
  ## Complete the genuine original guest computation and whole assured successor publication before attaching its already admitted block bytes.
  let source = assuredChainFixture(votes)
  var seed = source.assuredChainSeed
  let prior = seed.view
  let available = source.assuredCompositionSource.value.assuredExecutionSource.value.assuredQueueSource.value
  let candidate = available.computedAssuranceStage.value.value.admitted.admittedBlock
  let advanced = advanceAssuredChain(seed.state, seed.view, source)
  assert advanced.error == AssuredChainError.None, "whole genuine assured successor publication"
  let retained = advanced.value.assuredChainBlock.value
  let attached = withBlockBody(retained, candidate)
  assert attached.error == GenesisError.None, "retain original admitted body on actual whole successor state"
  let final = prior.advanceView(attached)
  assert final.error == ViewAdvanceError.None, "actual published successor with complete bytes"
  AuditContextFixture(view: final.value, prior: prior, blockHash: retained.blockHash,
      candidate: candidate)
proc auditLimits*(): AuditContextLimits =
  ## Maintained three-core transition policies accompany literal independent capture, comparison and retention budgets.
  let source = computedAssuranceConfig()
  AuditContextLimits(admission: source.admission, disputes: source.disputes,
    safrole: source.safrole,
    availability: source.availability,
    bodyBytes: ByteLimit(1000000), chapterBytes: ByteLimit(1000000), readBytes: ByteLimit(8000000),
    workspaceBytes: ByteLimit(128000000), outputBytes: ByteLimit(8000000), reports: ElementLimit(3),
    hashes: ElementLimit(6), hashBytes: ByteLimit(1000000))
