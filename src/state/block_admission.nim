# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## GP 0.8.0 header.tex parent/state/extrinsic bindings over one immutable decoded block.
## This is a full-state admission boundary, not complete block validity or disputes execution.
import std/assertions
import ../codec/[block_codec, header, bounded, state_safrole, state_layout, state_trie]
from ../codec/disputes import OffenderKey
import ../crypto/[primitives, extrinsic_commitment]
import ./[store, safrole_transition]

type
  ## Caller-selected C.2 profile and independent parent-header ceiling; no domain is inferred from bytes.
  BlockAdmissionConfig* = object
    frame*: FrameConfig
    maxParentHeaderBytes*: ByteLimit
  ## Only the completed alternative carries a binding; all rejected comparisons retain a reason alone.
  BlockAdmissionError* {.pure.} = enum
    Uninitialized, None, InvalidConfig, InvalidBlock, InvalidParent, MissingState, InvalidState,
    InvalidSlot, InvalidParentHash, InvalidStateRoot, InvalidExtrinsicHash,
    LimitExceeded, LengthOverflow, BackendFailure
  ## Acyclic immutable binding retains the exact block, its decoded header, supplied parent and full-state snapshot.
  BindingData = ref object
    candidate: OwnedBlock
    header: OwnedHeader
    parent: OwnedHeader
    state: StateStoreSnapshot
  ## Private identity cannot be forged by supplying disconnected headers, tickets or detached byte spans.
  BoundBlock* = object
    data: nil BindingData
  ## Default/failed alternatives contain no bound owner or comparison progress.
  BlockAdmissionResult* = object
    case status: BlockAdmissionError
    of None:
      completed: BoundBlock # All three commitments and chronology matched this exact captured block.
    else:
      discard               # No preflight or primitive refusal fabricates a successful binding.
  ## Success retains the bound input together with the Safrole stage's immutable published state/header.
  BlockSafroleUpdate* = object
    admitted*: BoundBlock
    transition*: SafroleTransition
  ## Composition preserves the precise admission or Safrole refusal without a partial snapshot.
  BlockSafroleError* {.pure.} = enum
    Uninitialized, None, AdmissionFailure, SafroleFailure
  ## Nested failed Safrole results contain only their existing checked stage reason.
  BlockSafroleResult* = object
    case status: BlockSafroleError
    of None:
      completed: BlockSafroleUpdate        # No mutable store handle escapes publication.
    of AdmissionFailure:
      admissionReason: BlockAdmissionError # Admission never returns success in this branch.
    of SafroleFailure:
      stageReason: SafroleTransitionResult # Only a refused stage can populate this alternative.
    else:
      discard                              # Default results cannot expose input or posterior state.

## Inspect admission refusal without granting retagging or access to an invalid binding.
func error*(outcome: BlockAdmissionResult): BlockAdmissionError = outcome.status
## Retain the completed binding only after selecting success.
func value*(outcome: BlockAdmissionResult): BoundBlock {.inline,
    requires: outcome.status == BlockAdmissionError.None.} = outcome.completed
## Inspect composed stage status without extracting an unselected reason.
func error*(outcome: BlockSafroleResult): BlockSafroleError = outcome.status
## Extract complete composed success only.
func value*(outcome: BlockSafroleResult): BlockSafroleUpdate {.inline,
    requires: outcome.status == BlockSafroleError.None.} = outcome.completed
## Read the exact admission cause only after selecting that failed stage.
func admissionError*(outcome: BlockSafroleResult): BlockAdmissionError {.inline,
    requires: outcome.status == BlockSafroleError.AdmissionFailure.} = outcome.admissionReason
## Read the existing typed Safrole failure only after selecting its refusal alternative.
func safroleError*(outcome: BlockSafroleResult): SafroleTransitionResult {.inline,
    requires: outcome.status == BlockSafroleError.SafroleFailure.} = outcome.stageReason

## Retain the same immutable block after binding, independently of caller handles and source buffers.
proc admittedBlock*(binding: BoundBlock): OwnedBlock {.requires: binding.data != nil.} =
  let data = binding.data
  assert data != nil # Bind the checked ARC owner once before extraction.
  data.candidate
## Retain the exact header that was extracted from this block, never an independently supplied candidate.
proc admittedHeader*(binding: BoundBlock): OwnedHeader {.requires: binding.data != nil.} =
  let data = binding.data
  assert data != nil # Preserve the owner throughout the copied handle access.
  data.header
## Retain the parent header whose complete sealed serialization matched the candidate's parent identity.
proc admittedParent*(binding: BoundBlock): OwnedHeader {.requires: binding.data != nil.} =
  let data = binding.data
  assert data != nil # A default binding cannot substitute for genesis context.
  data.parent
## Retain the exact complete-map snapshot whose commitment and timeslot matched the header context.
proc admittedState*(binding: BoundBlock): StateStoreSnapshot {.requires: binding.data != nil.} =
  let data = binding.data
  assert data != nil # No partial light map is promoted to a full-state root.
  data.state

## Revalidate the captured block under caller policy, then bind parent hash, complete state root and extrinsic hash.
## Parent is trusted chain context supplied by the caller; this function does not establish chain ancestry/consensus.
proc validateBlockCommitments*(candidate: OwnedBlock, parent: OwnedHeader,
    state: StateStoreSnapshot, config: BlockAdmissionConfig): BlockAdmissionResult =
  let info = blockInfo(candidate)
  if info.error != FrameError.None:
    return BlockAdmissionResult(status: BlockAdmissionError.InvalidBlock) # Default is not a complete decoded block.
  let parentInfo = headerInfo(parent)
  if parentInfo.error != HeaderError.None:
    return BlockAdmissionResult(status: BlockAdmissionError.InvalidParent) # A genesis/trusted parent still needs exact full header bytes.
  if uint64(info.value.consumed) > uint64(config.frame.maxBytes) or
      uint64(parentInfo.value.consumed) > uint64(config.maxParentHeaderBytes):
    return BlockAdmissionResult(status: BlockAdmissionError.LimitExceeded) # Bound both copies before materializing either input.
  let time = state.lookup(chapterKey(StateChapter(11)))
  if time.error != StateStoreError.None:
    return BlockAdmissionResult(status: if time.error == StateStoreError.Uninitialized:
      BlockAdmissionError.Uninitialized else: BlockAdmissionError.MissingState) # Missing state is never synthesized.
  if time.value.byteLength != 4:
    return BlockAdmissionResult(status: BlockAdmissionError.InvalidState) # Fixed state-time suffixes/truncations are not accepted.
  let previous = decodeStateTime(time.value.bytes)
  if previous.error != StateComponentError.None:
    return BlockAdmissionResult(status: BlockAdmissionError.InvalidState) # No unselected fixed-codec payload.
  if uint32(previous.value.value) != uint32(parentInfo.value.unsigned.slot):
    return BlockAdmissionResult(status: BlockAdmissionError.InvalidState) # A root alone cannot pair another slot's state with the parent header.
  var wire = newSeq[byte](info.value.consumed)
  let written = encodeOwnedBlock(candidate, wire)
  if written.error != FrameError.None:
    return BlockAdmissionResult(status: BlockAdmissionError.InvalidBlock) # Never hash a failed or partial serialization.
  let captured = decodeBlock(wire, config.frame)
  if captured.error != FrameError.None:
    return BlockAdmissionResult(status: if captured.error == FrameError.InvalidConfig:
      BlockAdmissionError.InvalidConfig else: BlockAdmissionError.InvalidBlock) # A permissive captured profile cannot bypass current application policy.
  if captured.value.consumed != wire.len:
    return BlockAdmissionResult(status: BlockAdmissionError.InvalidBlock) # The binding covers one complete exact block only.
  let exact = captured.value.owner
  let header = readHeader(blockHeader(exact).value)
  if header.error != HeaderError.None:
    return BlockAdmissionResult(status: BlockAdmissionError.InvalidBlock) # A valid immutable frame must yield its full sealed header.
  let fields = headerInfo(header.value.owner).value.unsigned
  if uint32(fields.slot) <= uint32(parentInfo.value.unsigned.slot):
    return BlockAdmissionResult(status: BlockAdmissionError.InvalidSlot) # No repeated, backward or wrapped child slots.
  if array[32, byte](fields.priorState) != array[32, byte](state.commitment.root):
    return BlockAdmissionResult(status: BlockAdmissionError.InvalidStateRoot) # Compare the parent posterior state, not the parent's own prior-state field.
  var parentWire = newSeq[byte](parentInfo.value.consumed)
  let encodedParent = encodeOwnedHeader(parent, parentWire)
  if encodedParent.error != HeaderError.None:
    return BlockAdmissionResult(status: BlockAdmissionError.InvalidParent) # The seal is included in full parent serialization.
  let parentHash = blake2b256(parentWire)
  if parentHash.error != CryptoError.None:
    return BlockAdmissionResult(status: BlockAdmissionError.BackendFailure) # Backend refusal cannot become a mismatched or zero parent identity.
  if array[32, byte](fields.parent) != array[32, byte](parentHash.value):
    return BlockAdmissionResult(status: BlockAdmissionError.InvalidParentHash) # No unsigned-header or whole-parent-block hash fallback.
  let commitment = extrinsicCommitment(blockExtrinsic(exact).value, config.frame.maxBytes)
  if commitment.error != ExtrinsicCommitmentError.None:
    let reason = case commitment.error
      of ExtrinsicCommitmentError.LimitExceeded: BlockAdmissionError.LimitExceeded # Projection expansion has an independent aggregate bound.
      of ExtrinsicCommitmentError.LengthOverflow: BlockAdmissionError.LengthOverflow # Native sizes must remain representable.
      of ExtrinsicCommitmentError.BackendFailure: BlockAdmissionError.BackendFailure # Never consume a failed hash.
      else: BlockAdmissionError.InvalidBlock # A missing materialized child is invalid ownership.
    return BlockAdmissionResult(status: reason)
  if array[32, byte](fields.extrinsics) != array[32, byte](commitment.value):
    return BlockAdmissionResult(status: BlockAdmissionError.InvalidExtrinsicHash) # Every exact family, credential and payload contributes under header.tex.
  BlockAdmissionResult(status: BlockAdmissionError.None,
    completed: BoundBlock(data: BindingData(candidate: exact, header: header.value.owner,
      parent: parent, state: state)))

## Bind one immutable block to the current parent state, then extract its own tickets for atomic Safrole.
## Posterior disputes offenders remain supplied; other extrinsic execution, wall clock and block import are separate.
proc advanceBlockSafrole*(state: var StateStore, candidate: OwnedBlock, parent: OwnedHeader,
    offenders: openArray[OffenderKey], config: BlockAdmissionConfig,
    safrole: SafroleTransitionConfig): BlockSafroleResult =
  if uint64(config.frame.cores) != uint64(safrole.state.validators.cores) or
      uint64(config.frame.validators) != uint64(safrole.state.validators.validators) or
      uint64(config.frame.epochSlots) != uint64(safrole.state.epochSlots) or
      uint64(config.frame.ticketLimit) != uint64(safrole.blockTickets):
    return BlockSafroleResult(status: BlockSafroleError.AdmissionFailure,
      admissionReason: BlockAdmissionError.InvalidConfig) # Shared chain domains cannot diverge between decoding and state execution.
  let retained = state.snapshot
  if retained.error != StateStoreError.None:
    return BlockSafroleResult(status: BlockSafroleError.AdmissionFailure,
      admissionReason: BlockAdmissionError.Uninitialized) # Default handles have no parent snapshot.
  let bound = validateBlockCommitments(candidate, parent, retained.value, config)
  if bound.error != BlockAdmissionError.None:
    return BlockSafroleResult(status: BlockSafroleError.AdmissionFailure,
      admissionReason: bound.error) # No comparison failure can reach any native Safrole work or state write.
  let exact = bound.value
  let tickets = readTickets(extrinsicTickets(blockExtrinsic(exact.admittedBlock).value).value)
  if tickets.error != FrameError.None:
    return BlockSafroleResult(status: BlockSafroleError.AdmissionFailure,
      admissionReason: BlockAdmissionError.InvalidBlock) # No separately supplied or partially extracted ticket batch.
  let advanced = advanceSafroleState(state, exact.admittedHeader, tickets.value, offenders, safrole)
  if advanced.error != SafroleTransitionError.None:
    return BlockSafroleResult(status: BlockSafroleError.SafroleFailure,
      stageReason: advanced) # The coordinator already preserves the entire canonical map/root on refusal.
  BlockSafroleResult(status: BlockSafroleError.None,
    completed: BlockSafroleUpdate(admitted: exact, transition: advanced.value))
