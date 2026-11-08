# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Genuine original report execution, credential admission, full computed-chain publication and exact retained availability provenance supply canonical assurance acquisition fixtures.

import std/assertions
import ../../src/chain/[genesis, provider]
import ../../src/state/store
import ../../src/state/computed/[composition, finalization, execution, round, publication,
  admission, inclusion, batch, envelope, credentials, guarantors, roster, transition,
  profile, lookup, recent, state, links, guarantee, report, chain]
import ../../src/state/availability/specifier
import ../../src/codec/bounded
import ../../src/codec/state/[safrole, layout]
import ../../src/jamnp-s/[assurance_duty, assurance_record]
import ./[pvm_computed_chain, pvm_computed_state_publication, pvm_computed_storage_program]

type AssuranceAcquisitionFixture* = object ## Complete post-publication state and original genuine erasure data share no fabricated pending assignment or placeholder credential.
  source*: BlockSnapshotResult
  availability*: AvailabilityCommitment
  local*, other*: StateEdKey
  chain*: AssuranceChainId

proc assuranceAcquisitionFixture*(): AssuranceAcquisitionFixture =
  ## Recover the source only through sealed computation getters, then publish its real pending report before selecting the local parent's roster identity.
  let composed = chainFixture(storage = ComputedStorageMode.Commit)
  let parent = composed.chainFixtureParent(composed.chainFixtureParameters)
  var state = forkStateStore(composed.statePublicationParent).value
  var view = genesisView(parent)
  let advanced = advanceComputedChain(state, view, composed)
  assert advanced.error == ComputedChainError.None, "genuine computed chain admission and publication"
  let head = advanced.value.computedChainBlock.value
  let source = captureBlockSnapshot(chainHeaderBytes(head.header), head.stateSnapshot,
      head.chainParameters)
  assert source.error == GenesisError.None, "exact published complete parent"
  let successor = composed.computedCompositionSource.value.computedFinalizationSource.value.computedExecutionSource.value.computedRoundSource.value
  let batch = successor.computedSuccessorSource.value.computedAdmissionSource.value.computedInclusionSource.value
  let credential = batch.computedBatchSourceAt(ComputedBatchIndex(
      0)).value.computedEnvelopeSource.value
  let original = credential.computedCredentialSource.value.computedGuarantorSource.value.computedRosterSource.value.computedTransitionSource.value
  let computed = original.computedProfileSource.value.computedLookupSource.value.computedRecentSource.value.computedStateSource.value.computedLinkSource.value.computedGuaranteeReport.value
  let available = computed.computedReportSource.value
  let roster = decodeStateValidators(head.lookup(chapterKey(StateChapter(8))).value.bytes,
    ValidatorStateConfig(cores: head.cores, validators: ElementLimit(1023), maxBytes: ByteLimit(1000000)))
  assert roster.error == StateComponentError.None, "actual parent active roster"
  let local = validatorAt(roster.value.value, StateValidatorIndex(1)).value.ed25519
  let other = validatorAt(roster.value.value, StateValidatorIndex(2)).value.ed25519
  AssuranceAcquisitionFixture(source: source, availability: available, local: local, other: other,
    chain: AssuranceChainId(array[32, byte](parent.value.blockHash)))
