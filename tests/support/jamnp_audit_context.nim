# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Genuinely computed, assured, accumulated and published successor state retains its original admitted body for audit-context qualification; no pending report or availability vote is fabricated.
import std/assertions
import ../../src/jamnp-s/[audit_context, audit_origin]
from ../../src/codec/state/trie import TrieNodeLimit
import ../../src/codec/[bounded, block_codec]
import ../../src/codec/state/[layout, safrole]
import ../../src/chain/[genesis, provider, reports]
import ../../src/crypto/primitives
import ../../src/state/computed/[composition, finalization, execution, round, publication,
  admission, inclusion, batch, envelope, credentials, guarantors, roster, transition,
  profile, lookup, recent, state, links, guarantee, report, chain]
import ../../src/state/computed/state/publication
import ../../src/state/availability/specifier
import "../../src/state/export/erasure"
import ../../src/state/[bundle_erasure, auditable_bundle]
import ../../src/state/erasure/layout
import ../../src/state/computed/assurances
import "../../src/state/block/admission"
import ../../src/state/assured/[chain, composition, execution, queue]
import ./[pvm_assured_chain, pvm_computed_assurances]
type OriginalAuditBundle* = object ## Raw test bytes and canonical report identity derive only from original genuine executed/guaranteed publication.
  reportHash*: WorkReportHash
  wire*: seq[byte]
type AuditContextFixture* = object ## Test-owned retained views contain actual complete publication, real body and independent predecessor authority.
  view*, prior*: ChainView
  blockHash*: genesis.BlockHash
  candidate*: OwnedBlock
  bundles*: seq[OriginalAuditBundle]
proc originalBundles(source: AssuredComputedReports): seq[OriginalAuditBundle] =
  ## Follow the exact admitted predecessor's computed batch back to every original availability commitment; no candidate bundle is independently fabricated.
  let composed = source.computedAssuranceSource.value.computedChainPublication.value.computedPublishedSource.value
  let successor = composed.computedCompositionSource.value.computedFinalizationSource.value.computedExecutionSource.value.computedRoundSource.value
  let batch = successor.computedSuccessorSource.value.computedAdmissionSource.value.computedInclusionSource.value
  result = @[]
  for ordinal in 0..<batch.computedBatchInfo.value.guarantees:
    let credential = batch.computedBatchSourceAt(ComputedBatchIndex(uint64(
        ordinal))).value.computedEnvelopeSource.value
    let original = credential.computedCredentialSource.value.computedGuarantorSource.value.computedRosterSource.value.computedTransitionSource.value
    let computed = original.computedProfileSource.value.computedLookupSource.value.computedRecentSource.value.computedStateSource.value.computedLinkSource.value.computedGuaranteeReport.value
    let available = computed.computedReportSource.value
    let bundle = available.availabilitySource.value.exportErasureSource.value.bundleErasureSource.value.layoutSource.value
    let hashed = blake2b256(computed.computedReportBytes.value)
    assert hashed.error == CryptoError.None, "original canonical computed report identity"
    result.add(OriginalAuditBundle(reportHash: WorkReportHash(array[32, byte](hashed.value)),
        wire: bundle.bundleBytes.value))
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
      candidate: candidate, bundles: originalBundles(available))
proc auditLimits*(): AuditContextLimits =
  ## Maintained three-core transition policies accompany literal independent capture, comparison and retention budgets.
  let source = computedAssuranceConfig()
  AuditContextLimits(admission: source.admission, disputes: source.disputes,
    safrole: source.safrole,
    availability: source.availability,
    bodyBytes: ByteLimit(1000000), chapterBytes: ByteLimit(1000000), readBytes: ByteLimit(8000000),
    workspaceBytes: ByteLimit(128000000), outputBytes: ByteLimit(8000000), reports: ElementLimit(3),
    hashes: ElementLimit(6), hashBytes: ByteLimit(1000000))

proc auditOriginLimits*(): AuditOriginLimits =
  ## Test-owned complete predecessor retention has explicit independent logical entry/node/value ceilings.
  AuditOriginLimits(entries: ElementLimit(10000), nodes: TrieNodeLimit(1000000),
      valueBytes: ByteLimit(8000000))
