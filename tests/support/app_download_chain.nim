# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Genuine finite signed chains derive each child from the previous complete composed state.
## This authored ordinary-epoch fixture never substitutes certificates or bypasses admission/execution.
import std/assertions
import std/syncio
import ../../src/app/chain as app_chain
import ../../src/app/candidate as app_candidate
import ../../src/chain/genesis as chain_genesis
import ../../src/chain/provider as chain_provider
import ../../src/codec/bounded as codec_bounded
import ../../src/codec/header as codec_header
import ../../src/codec/block_codec as codec_block_codec
import ../../src/codec/report_owned as codec_report_owned
import ../../src/codec/state_layout as codec_state_layout
import ../../src/codec/state_safrole as codec_state_safrole
import ../../src/state/store as state_store
import ../../src/state/block_transition as state_block_transition
import ../../src/state/safrole_transition as state_safrole_transition
import ../../src/state/accumulation_chain as state_accumulation_chain
import ../../src/state/accumulation_state as state_accumulation_state
import ../../src/state/accumulation_completion as state_accumulation_completion
import ../../src/crypto/extrinsic_commitment as crypto_extrinsic_commitment
import ../../src/bandersnatch/bandersnatch as bandersnatch_bandersnatch
import ./app_candidate_context
import ./state_accumulation_completion_context

type DownloadChainFixture* = object ## Independent expected heads retain complete maps for literal consumer comparison.
  seed*: SeedFixture
  children*: seq[OwnedBlock]
  heads*: seq[BlockSnapshot]

proc transcript(domain: string, seed: array[32, byte]): seq[byte] =
  ## Preserve the exact established signing-domain octets and fixed entropy word.
  result = newSeq[byte](domain.len + 32)
  for index, character in domain: result[index] = byte(character) # No count or terminator enters the VRF context.
  for index, octet in seed: result[domain.len + index] = octet

proc signedChild*(parent: BlockSnapshot): OwnedBlock =
  ## Author the next ordinary in-epoch child with genuine seal/entropy proofs over the actual current parent/root.
  let slot = uint32(parent.slot) + 1
  assert slot < 10 # This fixture intentionally excludes epoch/tail markers; production keeps its existing validators.
  let config = preparationLimits().reporting.admission.frame
  let headerConfig = preparationLimits().reporting.reports.ancestors.header
  let body = @[0'u8, 0, 0, 0, 0, 0, 0]
  let extrinsic = decodeExtrinsic(body, config)
  assert extrinsic.error == FrameError.None and extrinsic.value.consumed == body.len
  let state = parent.stateSnapshot
  let entropy = decodeStateEntropy(state.lookup(chapterKey(StateChapter(6))).value.bytes)
  assert entropy.error == StateComponentError.None, "complete parent entropy"
  var scalar = default(array[32, byte])
  scalar[0] = 1
  let key = importScalar(scalar).value
  let context = transcript("jam_fallback_seal", array[32, byte](entropy.value.value[3]))
  let provisional = sign(key, context, []).value
  let output = verify(publicKey(key).value, provisional, context, []).value
  var child = default(codec_header.Header)
  child.unsigned.epoch = absentEpoch()
  child.unsigned.winners = absentWinners()
  child.unsigned.parent = HeaderParent(array[32, byte](parent.blockHash))
  child.unsigned.priorState = PriorStateRoot(array[32, byte](state.commitment.root))
  child.unsigned.extrinsics = ExtrinsicRoot(array[32, byte](extrinsicCommitment(
    extrinsic.value.owner,
    config.maxBytes).value))
  child.unsigned.slot = HeaderSlot(slot)
  child.unsigned.entropyProof = HeaderEntropyProof(array[96, byte](sign(key,
    transcript("jam_entropy", array[32, byte](output)), []).value))
  var unsigned = newSeq[byte](100000)
  let unsignedSize = encodeUnsignedHeader(child.unsigned, headerConfig, unsigned).value
  unsigned.setLen(unsignedSize)
  child.seal = HeaderSeal(array[96, byte](sign(key, context, unsigned).value))
  var wire = newSeq[byte](100000)
  let size = encodeHeader(child, headerConfig, wire).value
  wire.setLen(size)
  for octet in body: wire.add(octet) # The full exact empty extrinsic follows its real sealed header.
  let decoded = decodeBlock(wire, config)
  assert decoded.error == FrameError.None and decoded.value.consumed == wire.len
  decoded.value.owner

proc chainCompositionLimits*(): AccumulationCompositionLimits =
  ## The original single-child fixture permits one prior service-statistics row; later parents legitimately contain two.
  result = completionLimits().composition
  result.validators.services = ElementLimit(4) # Explicitly cover evolved parent state without changing legacy fixture defaults.

proc chainFixture*(base: OwnedReport, count: Positive = 3): DownloadChainFixture =
  ## Derive each expected complete head through the existing manual in-memory execution/composition path.
  assert count <= 8
  result = default(DownloadChainFixture)
  result.seed = fixture(base)
  var working = initialized(result.seed)
  result.heads.add(working.chainView.bestBlock.value)
  var ancestors: seq[OwnedHeader] = @[]
  for index in 0..<count:
    let before = working.chainView.bestBlock.value
    let child = if index == 0: candidateBlock(result.seed) else: signedChild(before)
    let prepared = prepareCandidate(working, child, ancestors, preparationLimits())
    if prepared.error != ApplicationCandidateError.None:
      echo "CHAIN preparation index=" & $index & " error=" & $prepared.error
      if prepared.error == ApplicationCandidateError.BlockFailure:
        echo "CHAIN block=" & $prepared.blockFailure.error
        if prepared.blockFailure.error == BlockTransitionError.SafroleFailure:
          echo "CHAIN safrole=" & $prepared.blockFailure.safroleError.error
          if prepared.blockFailure.safroleError.error ==
              SafroleTransitionError.AuthenticationFailure:
            echo "CHAIN authentication=" & $prepared.blockFailure.safroleError.authenticationError
    assert prepared.error == ApplicationCandidateError.None, "genuine sequential candidate preparation"
    let installed = working.applyAccumulation(prepared.value, chainCompositionLimits())
    if installed.error != ApplicationChainError.None:
      echo "CHAIN composition index=" & $index & " error=" & $installed.error
      if installed.error == ApplicationChainError.ChainFailure:
        let failed = installed.chainFailure
        echo "CHAIN chain=" & $failed.error
        if failed.error == AccumulationChainError.ApplicationFailure:
          echo "CHAIN application=" & $failed.applicationFailure.error
          if failed.applicationFailure.error == AccumulationStateError.CompositionFailure:
            echo "CHAIN phase=" & $failed.applicationFailure.compositionFailure.error
    assert installed.error == ApplicationChainError.None, "sequential full-state composition"
    result.children.add(child)
    result.heads.add(installed.value)
    var next = @[before.header]
    for older in ancestors: next.add(older) # Every old selected header becomes the next child's newest older header.
    ancestors = next

proc responseFrame*(child: OwnedBlock): seq[byte] =
  ## Encode CE's E4 length and complete signed child without production transport helpers.
  let size = child.blockInfo.value.consumed
  result = newSeq[byte](size + 4)
  for index in 0..<4: result[index] = byte((uint64(size) shr (8 * index)) and 255)
  assert encodeOwnedBlock(child, result.toOpenArray(4, result.high)).error == FrameError.None

proc expectedRequest*(parent: BlockSnapshot): array[42, byte] =
  ## Independently spell CE128: 37-byte request, exact selected hash, ascending direction and maximum one.
  result = default(array[42, byte])
  result[0] = 128
  result[1] = 37
  for index, octet in array[32, byte](parent.blockHash): result[5 + index] = octet
  result[38] = 1

proc sameCompleteState*(left, right: StateStoreSnapshot): bool =
  ## Compare every serialized entry as well as the complete root; missing values cannot masquerade as equal prefixes.
  if array[32, byte](left.commitment.root) != array[32, byte](right.commitment.root) or
      left.commitment.entries != right.commitment.entries: return false
  for index in 0..<right.commitment.entries:
    let key = right.keyAt(StateEntryIndex(index)).value
    let found = left.lookup(key)
    if found.error != StateStoreError.None or found.value.bytes != right.lookup(key).value.bytes:
      return false # Exact complete map equality is stronger than the retained expected root alone.
  true
