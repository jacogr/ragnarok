# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Author a real guarantee-bearing candidate, authenticate its prefix, then bind and verify the original computations anew.

import std/assertions
import ../../src/state/[computed_batch, computed_envelope, computed_credentials,
  computed_guarantors,
  computed_roster, computed_transition, computed_profile, computed_lookup, computed_recent,
  computed_state, computed_links, block_transition, block_admission, store]
import ../../src/chain/genesis
import ../../src/codec/[bounded, header, block_codec, guarantees, assurances]
import ../../src/crypto/extrinsic_commitment
import ../../src/bandersnatch/bandersnatch
import ./[pvm_computed_batch, pvm_computed_roster, pvm_computed_credentials,
  pvm_computed_guarantors,
  pvm_computed_recent, pvm_computed_lookup]

proc inclusionFixture*(changed = false, distinctPackages = false,
    withReady = false): ComputedGuaranteeBatch =
  ## Raw proposals author the candidate only; returned authority is rederived from its actual signed prefix.
  let proposals = batchEnvelopes(distinctPackages = distinctPackages, withReady = withReady)
  let proposed = prepareComputedBatch(proposals, batchLimits()).value
  let first = proposals[0].computedEnvelopeSource.value.computedCredentialSource.value.computedGuarantorSource.value.computedRosterSource.value
  let original = first.computedTransitionSource.value.computedProfileContext.value
  let oldStage = first.computedTransitionStage.value.value
  let cfg = rosterTransitionConfig()
  let parent = oldStage.admitted.admittedParent
  let oldCandidate = oldStage.admitted.admittedBlock
  let oldExtrinsic = oldCandidate.blockExtrinsic.value
  var guaranteeWire = proposed.computedBatchBytes.value
  if changed:
    # A canonical but wrong signature is allowed in raw proposal bytes; final credentials still derive from genuine verification.
    guaranteeWire[guaranteeWire.len-1] = guaranteeWire[guaranteeWire.len-1] xor 1
  let guarantee = decodeComponent[ComponentKind.Guarantees](guaranteeWire,
      cfg.admission.frame).value.owner
  let extrinsic = ownExtrinsic(Extrinsic(tickets: oldExtrinsic.extrinsicTickets.value,
    preimages: oldExtrinsic.extrinsicPreimages.value, guarantees: guarantee,
    assurances: oldExtrinsic.extrinsicAssurances.value,
    disputes: oldExtrinsic.extrinsicDisputes.value), cfg.admission.frame).value
  let header = oldStage.admitted.admittedHeader
  var headerWire = newSeq[byte](headerInfo(header).value.consumed)
  assert encodeOwnedHeader(header, headerWire).error == HeaderError.None
  let commitment = array[32, byte](extrinsicCommitment(extrinsic, ByteLimit(100000)).value)
  for i in 0..<32: headerWire[64+i] = commitment[i] # E32 parent and E32 prior-state root precede extrinsic commitment.
  var scalar = default(array[32, byte])
  scalar[0] = 1
  let key = importScalar(scalar).value
  var context = newSeq[byte]("jam_fallback_seal".len+32)
  for i, octet in "jam_fallback_seal": context[i] = byte(octet) # Literal domain plus fixed zero seed.
  let seal = array[96, byte](sign(key, context, headerWire.toOpenArray(0, headerWire.len-97)).value)
  close(key)
  for i in 0..<96: headerWire[headerWire.len-96+i] = seal[
      i] # Sign the actual unsigned header after committing the full proposed body.
  let component = decodeComponent[ComponentKind.Header](headerWire, cfg.admission.frame).value.owner
  var wire = newSeq[byte](100000)
  let written = encodeBlock(Block(header: component, extrinsic: extrinsic), cfg.admission.frame, wire).value
  let candidate = decodeBlock(wire.toOpenArray(0, written-1), cfg.admission.frame).value.owner
  var working = forkStateStore(original.state).value
  let staged = advanceBlockState(working, candidate, parent, cfg.admission, cfg.disputes,
      cfg.safrole, cfg.availability)
  assert staged.error == BlockTransitionError.None, "actual guarantee-bearing candidate prefix"
  let admitted = validateBlockCommitments(candidate, parent, original.state, cfg.admission)
  assert admitted.error == BlockAdmissionError.None, "actual body commitment and original map"
  var sources: seq[ComputedGuaranteeEnvelope] = @[]
  for proposal in proposals:
    # Reuse original executed links, never treat the earlier empty-candidate certificate as final inclusion authority.
    let previous = proposal.computedEnvelopeSource.value.computedCredentialSource.value.computedGuarantorSource.value.computedRosterSource.value.computedTransitionSource.value.computedProfileSource.value
    let links = previous.computedLookupSource.value.computedRecentSource.value.computedStateSource.value
    var older: seq[OwnedHeader] = @[]
    for i in 1..<previous.computedLookupInfo.value.headers:
      older.add(previous.computedLookupHeader(ComputedAncestorIndex(uint64(i))).value)
    let state = bindComputedState(links, admitted).value
    var history = recentConfig()
    history.cores = CoreCount(3)
    let recent = checkComputedRecentAnchor(state, history).value
    let lookup = checkComputedLookupAnchor(recent, older, lookupLimits()).value
    var parentWire = newSeq[byte](headerInfo(parent).value.consumed)
    assert encodeOwnedHeader(parent, parentWire).error == HeaderError.None
    let configured = bindComputedProfile(lookup, captureBlockSnapshot(parentWire, original.state,
        original.parameters)).value
    let bound = bindComputedTransition(configured, staged, ByteLimit(4096)).value
    let eligible = checkComputedRoster(bound, guarantorLimits().roster).value
    let context = prepareComputedGuarantors(eligible, guarantorLimits()).value
    let old = proposal.computedEnvelopeGuarantee.value
    let verified = verifyComputedCredentials(context, old.slot, old.credentials.toOpenArray(0,
        old.credentialCount-1)).value
    sources.add(prepareComputedEnvelope(verified, ComputedEnvelopeLimits(reportBytes: ByteLimit(
        100000),
      bytes: ByteLimit(100000), reporters: ElementLimit(3))).value)
  prepareComputedBatch(sources, batchLimits()).value
