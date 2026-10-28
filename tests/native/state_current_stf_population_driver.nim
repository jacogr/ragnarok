# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Complete three-core original maps and real culprit/resize candidates expose population-ceiling and offender semantics.
import std/assertions
import std/cmdline
import std/syncio
import ../support/state_current_stf_epoch_context as epoch
import ../../src/app/chain as app_chain
import ../../src/app/candidate as app_candidate
import ../../src/app/current_block_input as app_current_block_input
import ../../src/app/current_block_download as app_current_block_download
import ../../src/chain/genesis as chain_genesis
import ../../src/chain/provider as chain_provider
import ../../src/codec/bounded as codec_bounded
import ../../src/codec/state_layout as codec_state_layout
import ../../src/codec/state_safrole as codec_state_safrole
import ../../src/codec/state_consensus as codec_state_consensus
import ../../src/codec/state_authorization as codec_state_authorization
import ../../src/codec/state_availability as codec_state_availability
import ../../src/codec/state_statistics as codec_state_statistics
import ../../src/codec/state_privileges as codec_state_privileges
import ../../src/codec/state_disputes as codec_state_disputes
import ../../src/codec/disputes as codec_disputes
import ../../src/codec/report_owned as codec_report_owned
import ../../src/codec/block_codec as codec_block_codec
import ../../src/codec/header as codec_header
import ../../src/codec/state_composition as codec_state_composition
import ../../src/state/store as state_store
import ../../src/state/accumulation_current_update as state_accumulation_current_update
import ../../src/state/current_profile as state_current_profile
import ../../src/state/current_globals as state_current_globals
import ../../src/state/current_state as state_current_state
import ../../src/state/global_snapshot as state_global_snapshot
import ../../src/state/block_transition as state_block_transition
import ../../src/state/disputes as state_disputes
import ../../src/state/safrole_transition as state_safrole_transition
import ../../src/state/safrole_authentication as state_safrole_authentication
import ../../src/crypto/primitives as crypto_primitives
import ../../src/bandersnatch/bandersnatch as bandersnatch_bandersnatch
import ../support/state_current_stf_population_context
import ../support/state_current_namespace_context
import ../support/state_accumulation_current_chain_context
import ../support/state_inventory_context

proc culprit(): tuple[wire: seq[byte], offenders: seq[OffenderKey]] =
  ## Secret fixture seed16 guarantees a report already classified bad in the original C5.
  var seed = default(array[32, byte])
  seed[0] = 16
  let key = importSeed(seed).value
  let offender = OffenderKey(array[32, byte](publicKey(key).value))
  let signature = DisputeSignature(array[64, byte](sign(key, epoch.context("jam_guarantee",
      default(array[32, byte]))).value))
  let evidence = Disputes(culprits: @[Culprit(target: default(DisputeHash), key: offender,
      signature: signature)])
  var wire = newSeq[byte](1000)
  let encoded = encodeDisputes(evidence, DisputeConfig(validators: ValidatorCount(9),
      maxBytes: ByteLimit(1000)), wire)
  assert encoded.error == DisputeError.None
  wire.setLen(encoded.value)
  (wire, @[offender])

proc refusedDispute(chain: ApplicationChain, candidate: OwnedBlock, reason: DisputesError) =
  ## Exact culprit/signature/marker refusals leave every canonical byte and selected head unchanged.
  let saved = epoch.checkpointHex(chain.stateSnapshot.value)
  let result = prepareCurrentCandidate(chain, candidate, [], populationLimits())
  assert result.error == CurrentCandidateError.PrefixFailure
  assert result.prefixFailure.error == ApplicationCandidateError.BlockFailure
  let failure = result.prefixFailure.blockFailure
  assert failure.error == BlockTransitionError.DisputesFailure
  assert failure.disputesError == reason
  assert epoch.checkpointHex(chain.stateSnapshot.value) == saved

proc profiles(chain: ApplicationChain, candidate: OwnedBlock, size: int) =
  ## Candidate, fragmented input and download accept ceiling-nine and reject impossible/undersized capacities.
  let limits = populationLimits()
  let resources = CurrentBlockInputLimits(blockBytes: ByteLimit(100000), ancestors: ElementLimit(4),
      ancestorBytes: ByteLimit(100000))
  var input = default(CurrentBlockInput)
  assert input.begin(chain, ByteLimit(uint64(size)), [], resources, limits).error ==
      CurrentBlockInputError.None
  var download = default(CurrentBlockDownload)
  assert download.begin(chain, [], resources, limits).error == CurrentBlockDownloadError.None
  for ceiling in [3'u64, 8, 12]:
    var narrow = limits
    narrow.reporting.admission.frame.validators = ValidatorCount(ceiling)
    let result = prepareCurrentCandidate(chain, candidate, [], narrow)
    assert result.error == CurrentCandidateError.PrefixFailure
    assert result.prefixFailure.error == ApplicationCandidateError.ProfileMismatch
    var badInput = default(CurrentBlockInput)
    assert badInput.begin(chain, ByteLimit(uint64(size)), [], resources, narrow).error ==
        CurrentBlockInputError.ProfileMismatch
    var badDownload = default(CurrentBlockDownload)
    assert badDownload.begin(chain, [], resources, narrow).error ==
        CurrentBlockDownloadError.ProfileMismatch

proc main() {.raises.} =
  ## Generation exports only original input/root witnesses; normal verification executes genuine candidate admission.
  let raw = readFile(paramStr(1))
  var bytes = newSeq[byte](raw.len)
  for index, octet in raw: bytes[index] = byte(octet)
  let parent = populationOriginal(decodeOwnedReport(bytes, 2).value)
  let evidence = culprit()
  if paramStr(2) == "--generate":
    echo "P ", epoch.checkpointHex(parent.stateSnapshot)
    let setup = newSetup(9).value
    let staging = decodeStateValidators(parent.stateSnapshot.lookup(chapterKey(StateChapter(
        7))).value.bytes, populationLimits().reporting.safrole.state.validators).value.value
    var filtered: seq[StateValidator] = @[]
    for index in 0..<6:
      var record = validatorAt(staging, StateValidatorIndex(uint64(index))).value
      if array[32, byte](record.ed25519) == array[32, byte](evidence.offenders[
          0]): record = nullValidator()
      filtered.add(record)
    echo "R ", epoch.hex(array[144, byte](commitRing(setup, epoch.members(filtered)).value))
    close(setup)
  else:
    let captured = captureBlockSnapshot(currentChainBytes(parent.header), parent.stateSnapshot,
        populationParameters())
    var chain = initApplicationChain(genesisView(captured)).value
    let saved = epoch.checkpointHex(parent.stateSnapshot)
    echo "P ", saved
    for slot in [2'u32, 11, 12, 13, 24, 25]:
      let prior = chain.chainView.bestBlock.value
      let body = if slot == 2: evidence.wire else: @[0'u8, 0, 0]
      let offenders = if slot == 2: evidence.offenders else: @[]
      let candidate = epoch.child(prior, slot, @[], @[], limits = populationLimits(),
          disputeWire = body, newOffenders = offenders)
      if slot == 2:
        refusedDispute(chain, epoch.child(prior, slot, @[], @[], limits = populationLimits(),
            disputeWire = body), DisputesError.InvalidMarker)
        var damaged = body
        damaged[damaged.len-2] = damaged[damaged.len-2] xor 1
        refusedDispute(chain, epoch.child(prior, slot, @[], @[], limits = populationLimits(),
            disputeWire = damaged, newOffenders = offenders), DisputesError.InvalidSignature)
      elif slot == 11:
        refusedDispute(chain, epoch.child(prior, slot, @[], @[], limits = populationLimits(),
            disputeWire = evidence.wire, newOffenders = evidence.offenders),
                DisputesError.InvalidKey)
      var wire = newSeq[byte](candidate.blockInfo.value.consumed)
      assert candidate.encodeOwnedBlock(wire).error == FrameError.None
      profiles(chain, candidate, wire.len)
      echo "B ", epoch.hex(wire)
      let prepared = prepareCurrentCandidate(chain, candidate, [], populationLimits())
      assert prepared.error == CurrentCandidateError.None, $prepared.error
      let update = prepared.value
      let profile = captureCurrentProfile(update, CurrentProfileLimits(validators: ElementLimit(
          1024), bytes: ByteLimit(65536))).value
      let globals = qualifyCurrentGlobals(profile, GlobalStateLimits(chapter: StateChapterPolicy(
          items: ElementLimit(10000), maxBytes: ByteLimit(65536)), totalBytes: ByteLimit(262144))).value
      assert qualifyCurrentState(globals, currentNamespaceServices(update.currentUpdateState,
          namespaceSeeds()), inventoryCaptureLimits).error == CurrentStateError.None
      chain.installPrepared(update)
      echo "O ", epoch.checkpointHex(chain.stateSnapshot.value)
    let retained = epoch.checkpointHex(chain.stateSnapshot.value)
    let nullSlot = epoch.child(chain.chainView.bestBlock.value, 28, @[], @[],
        limits = populationLimits(), forceSecret = 1)
    let refused = prepareCurrentCandidate(chain, nullSlot, [], populationLimits())
    assert refused.error == CurrentCandidateError.PrefixFailure
    assert refused.prefixFailure.error == ApplicationCandidateError.BlockFailure
    let failure = refused.prefixFailure.blockFailure
    assert failure.error == BlockTransitionError.SafroleFailure
    assert failure.safroleError.error == SafroleTransitionError.AuthenticationFailure
    assert failure.safroleError.authenticationError == SafroleAuthError.InvalidAuthor
    assert epoch.checkpointHex(chain.stateSnapshot.value) == retained
    assert epoch.checkpointHex(parent.stateSnapshot) == saved

try:
  main() # A refused or incomplete resize never emits passing complete-map evidence.
except:
  quit(2)
