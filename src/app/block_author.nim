# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Native empty-block authoring from an exact complete parent. Rotation, fallback eligibility
## and markers use the ordinary GP components. Returned blocks grant no adoption authority.

import ../chain/[genesis, parameters]
import ../codec/[bounded, header, block_codec, state_layout, state_safrole,
  state_consensus, state_disputes]
import ../state/[store, validator_state, sealer_schedule, safrole_markers, safrole_transition]
import ../crypto/extrinsic_commitment
import ../bandersnatch/bandersnatch

type
  BlockAuthorError* {.pure.} = enum ## Failure/default alternatives expose no partially signed block or staged state.
    Uninitialized, None, InvalidProfile, InvalidSlot, InvalidState, LimitExceeded,
    RotationFailure, ScheduleFailure, MarkerFailure, NotEligible, TicketSchedule,
    CryptoFailure, EncodingFailure
  BlockAuthorResult* = object ## Only complete success retains immutable structurally decoded block bytes.
    case status: BlockAuthorError
    of None: completed: OwnedBlock
    else: discard # Refused authoring cannot publish a block or change its supplied parent.

func error*(outcome: BlockAuthorResult): BlockAuthorError =
  ## Read the selected immutable reason before extracting a block.
  outcome.status
func value*(outcome: BlockAuthorResult): OwnedBlock {.inline,
    requires: outcome.status == BlockAuthorError.None.} =
  ## A block still requires normal candidate validation before canonical adoption.
  outcome.completed
proc context(domain: string, seed: array[32, byte]): seq[byte] =
  ## GP tokens contain literal ASCII bytes followed by one fixed word, with no dollar or prefix.
  result = newSeq[byte](domain.len+32)
  for index, character in domain: result[index] = byte(character)
  for index, octet in seed: result[domain.len+index] = octet

proc authorEmptyBlock*(parent: BlockSnapshot, target: HeaderSlot, key: BsKey,
    frame: FrameConfig, policy: SafroleTransitionConfig): BlockAuthorResult =
  ## Borrow the owned parent and secret synchronously. Every speculative state write is private.
  ## Empty extrinsics preserve existing offenders; ticket-scheduled slots require a future ticket bank.
  if parent.fuzzSeedOnly:
    return BlockAuthorResult(status: BlockAuthorError.InvalidProfile) # Fuzz-only structural seed authority cannot author an ordinary child.
  let epoch = uint64(policy.state.epochSlots)
  if epoch == 0 or epoch != uint64(parent.epochSlots) or
      parent.chainParameters.get(coreCount) != uint64(frame.cores) or
      uint64(frame.epochSlots) != epoch or uint64(frame.validators) != uint64(
          policy.state.validators.cores)*3:
    return BlockAuthorResult(status: BlockAuthorError.InvalidProfile) # Never silently reinterpret another chain profile.
  if uint32(target) <= parent.slot:
    return BlockAuthorResult(status: BlockAuthorError.InvalidSlot) # Backward, repeated and wrapped slots cannot be authored.
  if uint64(frame.maxBytes) < 304:
    return BlockAuthorResult(status: BlockAuthorError.LimitExceeded) # A complete minimal block needs 304 bytes.
  let ceiling = min(min(uint64(policy.maxHeaderBytes), uint64(frame.maxBytes)-7), 1048576'u64)
  if ceiling < 297:
    return BlockAuthorResult(status: BlockAuthorError.LimitExceeded) # Prove bounded native allocation and complete block extent.
  let state = parent.stateSnapshot
  let oldChapter = state.lookup(chapterKey(StateChapter(4)))
  let oldEntropy = state.lookup(chapterKey(StateChapter(6)))
  let oldTime = state.lookup(chapterKey(StateChapter(11)))
  let judgments = state.lookup(chapterKey(StateChapter(5)))
  if oldChapter.error != StateStoreError.None or oldEntropy.error != StateStoreError.None or
      oldTime.error != StateStoreError.None or judgments.error != StateStoreError.None:
    return BlockAuthorResult(status: BlockAuthorError.InvalidState) # A complete required chapter is never synthesized.
  if uint64(oldChapter.value.byteLength) > uint64(policy.state.maxBytes) or
      oldEntropy.value.byteLength != 128 or oldTime.value.byteLength != 4 or
      uint64(judgments.value.byteLength) > ceiling:
    return BlockAuthorResult(status: BlockAuthorError.LimitExceeded) # Bound all copies before decoding state-derived counts.
  let entropy = decodeStateEntropy(oldEntropy.value.bytes)
  let previous = decodeStateTime(oldTime.value.bytes)
  let disputes = decodeDisputeState(judgments.value.bytes, DisputeStateConfig(
    perSet: policy.offenders, totalItems: policy.offenders, maxBytes: ByteLimit(ceiling)))
  if entropy.error != StateComponentError.None or previous.error != StateComponentError.None or
      disputes.error != DisputeStateError.None:
    return BlockAuthorResult(status: BlockAuthorError.InvalidState) # Decode every success before guarded extraction.
  if uint32(previous.value.value) != parent.slot or disputes.value.consumed !=
      judgments.value.byteLength:
    return BlockAuthorResult(status: BlockAuthorError.InvalidState) # Header clock and exact complete chapters must agree.
  let offenderCount = disputeStateInfo(disputes.value.snapshot).value.offenders
  var offenders = newSeq[OffenderKey](offenderCount)
  for index in 0..<offenders.len:
    offenders[index] = stateOffenderAt(disputes.value.snapshot, DisputeStateIndex(uint64(index))).value
  var working = forkStateStore(state).value
  let rotated = rotateValidatorState(working, StateTime(uint32(target)), offenders,
    ValidatorTransitionConfig(safrole: policy.state, offenders: policy.offenders))
  if rotated.error != ValidatorStateError.None:
    return BlockAuthorResult(status: BlockAuthorError.RotationFailure) # A private ring/roster failure leaves canonical state untouched.
  let staged = rotated.value.lookup(chapterKey(StateChapter(4)))
  let active = rotated.value.lookup(chapterKey(StateChapter(8)))
  if staged.error != StateStoreError.None or active.error != StateStoreError.None:
    return BlockAuthorResult(status: BlockAuthorError.InvalidState) # Successful rotation must retain complete consensus chapters.
  let crossed = uint64(uint32(target)) div epoch > uint64(parent.slot) div epoch
  let history2 = entropy.value.value[if crossed: 1 else: 2]
  let schedule = selectSafroleSchedule(oldChapter.value.bytes, staged.value.bytes,
    active.value.bytes, previous.value.value, StateTime(uint32(target)), history2,
    SealerScheduleConfig(state: policy.state, tailStart: policy.tailStart))
  if schedule.error != SealerScheduleError.None:
    return BlockAuthorResult(status: BlockAuthorError.ScheduleFailure) # Invalid contests or roster encodings cannot become fallback.
  let selected = safroleInfo(schedule.value).value
  if selected.kind != SealerKind.Keys:
    return BlockAuthorResult(status: BlockAuthorError.TicketSchedule) # No substitute signer or fallback for a winning ticket.
  let public = publicKey(key)
  if public.error != BsError.None:
    return BlockAuthorResult(status: BlockAuthorError.CryptoFailure) # Invalid/default secret handles have no identity.
  let expected = sealerKeyAt(schedule.value, SafroleStateIndex(uint64(uint32(
      target)) mod epoch)).value
  if array[32, byte](expected) != array[32, byte](public.value):
    return BlockAuthorResult(status: BlockAuthorError.NotEligible) # An ordinary non-owning slot is not a produced block.
  let roster = decodeStateValidators(active.value.bytes, policy.state.validators)
  if roster.error != StateComponentError.None:
    return BlockAuthorResult(status: BlockAuthorError.InvalidState) # Eligibility also requires an indexed posterior active record.
  var author = -1
  for index in 0..<validatorCount(roster.value.value).value:
    let record = validatorAt(roster.value.value, StateValidatorIndex(uint64(index))).value
    if author < 0 and array[32, byte](record.bandersnatch) == array[32, byte](public.value):
      author = index # Preserve the first matching ordinal without sorting or changing population.
  if author < 0 or author > int(high(uint16)):
    return BlockAuthorResult(status: BlockAuthorError.NotEligible) # A schedule key alone is not active-roster membership.
  let markers = deriveSafroleMarkers(oldChapter.value.bytes, staged.value.bytes,
    previous.value.value, StateTime(uint32(target)), entropy.value.value,
    SafroleMarkerConfig(state: policy.state, tailStart: policy.tailStart,
      maxMarkerBytes: policy.maxMarkerBytes))
  if markers.error != SafroleMarkerError.None:
    return BlockAuthorResult(status: BlockAuthorError.MarkerFailure) # Epoch markers use retained parent randomness and posterior pending keys.
  let epochInfo = epochMarkerInfo(markers.value.epochMarker).value
  let winnerInfo = winnersMarkerInfo(markers.value.winnersMarker).value
  var epochMarker = absentEpoch()
  if epochInfo.present:
    var validators = newSeq[EpochValidator](epochInfo.validators)
    for index in 0..<validators.len:
      validators[index] = epochValidatorAt(markers.value.epochMarker, index).value
    epochMarker = presentEpoch(epochInfo.entropy, epochInfo.ticketsEntropy, validators)
  var winners = absentWinners()
  if winnerInfo.present:
    var tickets = newSeq[WinningTicket](winnerInfo.tickets)
    for index in 0..<tickets.len:
      tickets[index] = winningTicketAt(markers.value.winnersMarker, index).value
    winners = presentWinners(tickets) # Marker derivation is authoritative even on a fallback epoch's closing boundary.
  let body = [0'u8, 0, 0, 0, 0, 0, 0]
  let extrinsic = decodeExtrinsic(body, frame)
  if extrinsic.error != block_codec.FrameError.None:
    return BlockAuthorResult(status: BlockAuthorError.EncodingFailure) # The body must satisfy the actual caller's complete frame policy.
  let commitment = extrinsicCommitment(extrinsic.value.owner, frame.maxBytes)
  if commitment.error != ExtrinsicCommitmentError.None:
    return BlockAuthorResult(status: BlockAuthorError.CryptoFailure) # Never use a placeholder extrinsic root.
  let sealContext = context("jam_fallback_seal", array[32, byte](entropy.value.value[
      if crossed: 2 else: 3]))
  let provisional = sign(key, sealContext, [])
  if provisional.error != BsError.None:
    return BlockAuthorResult(status: BlockAuthorError.CryptoFailure) # The VRF output depends on context, independently of header additional data.
  let output = verify(public.value, provisional.value, sealContext, [])
  if output.error != BsError.None:
    return BlockAuthorResult(status: BlockAuthorError.CryptoFailure) # Only a verified output seeds the entropy proof.
  let entropyProof = sign(key, context("jam_entropy", array[32, byte](output.value)), [])
  if entropyProof.error != BsError.None:
    return BlockAuthorResult(status: BlockAuthorError.CryptoFailure) # The entropy signature has empty additional data.
  var source = header.Header(unsigned: UnsignedHeader(parent: HeaderParent(array[32, byte](
      parent.blockHash)),
    priorState: PriorStateRoot(array[32, byte](state.commitment.root)),
    extrinsics: ExtrinsicRoot(array[32, byte](commitment.value)), slot: target,
    epoch: epochMarker, winners: winners, author: AuthorIndex(uint16(author)),
    entropyProof: HeaderEntropyProof(array[96, byte](entropyProof.value)), offenders: @[]))
  let headerConfig = HeaderConfig(cores: frame.cores, authorValidators: frame.validators,
    epochSlots: frame.epochSlots, maxBytes: policy.maxHeaderBytes)
  var wire = newSeq[byte](int(ceiling))
  let unsigned = encodeUnsignedHeader(source.unsigned, headerConfig, wire)
  if unsigned.error != HeaderError.None:
    return BlockAuthorResult(status: BlockAuthorError.EncodingFailure) # No partial signing buffer escapes a codec refusal.
  wire.setLen(unsigned.value)
  let seal = sign(key, sealContext, wire)
  if seal.error != BsError.None:
    return BlockAuthorResult(status: BlockAuthorError.CryptoFailure) # Seal binds the entire exact unsigned header.
  source.seal = HeaderSeal(array[96, byte](seal.value))
  wire.setLen(int(ceiling))
  let encoded = encodeHeader(source, headerConfig, wire)
  if encoded.error != HeaderError.None:
    return BlockAuthorResult(status: BlockAuthorError.EncodingFailure) # Complete sealed header must fit the independent bound.
  wire.setLen(encoded.value)
  for octet in body: wire.add(octet)
  let captured = decodeBlock(wire, frame)
  if captured.error != block_codec.FrameError.None or captured.value.consumed != wire.len:
    return BlockAuthorResult(status: BlockAuthorError.EncodingFailure) # Return only an immutable exact complete block.
  BlockAuthorResult(status: BlockAuthorError.None, completed: captured.value.owner)
