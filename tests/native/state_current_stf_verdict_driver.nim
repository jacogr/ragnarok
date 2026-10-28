# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Signed verdict/fault inputs exercise complete candidate execution; only the independent oracle owns expected maps.
import std/assertions
import std/cmdline
import std/strutils
import std/parseutils
import std/syncio
import ../support/state_current_stf_epoch_context as epoch
import ../support/state_current_stf_population_context
import ../support/state_current_namespace_context
import ../support/state_inventory_context
import ../support/state_accumulation_current_chain_context
import ../../src/app/chain as app_chain
import ../../src/app/candidate as app_candidate
import ../../src/chain/genesis as chain_genesis
import ../../src/chain/provider as chain_provider
import ../../src/codec/bounded as codec_bounded
import ../../src/codec/report_owned as codec_report_owned
import ../../src/codec/block_codec as codec_block_codec
import ../../src/codec/state_layout as codec_state_layout
import ../../src/codec/disputes as codec_disputes
import ../../src/codec/state_disputes as codec_state_disputes
import ../../src/codec/state_composition as codec_state_composition
import ../../src/state/store as state_store
import ../../src/state/block_transition as state_block_transition
import ../../src/state/disputes as state_disputes
import ../../src/state/accumulation_current_update as state_accumulation_current_update
import ../../src/state/current_profile as state_current_profile
import ../../src/state/current_globals as state_current_globals
import ../../src/state/current_state as state_current_state
import ../../src/state/global_snapshot as state_global_snapshot
import ../../src/state/report_admission as state_report_admission

proc number(text: string): uint32 {.raises.} =
  ## Trusted request slots still require complete E4 conversion rather than an unchecked narrowing cast.
  let value = parseInt(text)
  assert value >= 0 and uint64(value) <= uint64(high(uint32))
  uint32(value)

proc offenders(text: string): seq[OffenderKey] =
  ## Preserve marker order and cross-section repeats; the actual disputes stage must verify this supplied sequence.
  result = @[]
  if text == "-": return # Empty marker is distinct from one all-zero identity.
  let bytes = epoch.unhex(text)
  assert bytes.len mod 32 == 0
  for index in 0..<bytes.len div 32:
    var key = default(array[32, byte])
    for at in 0..<32: key[at] = bytes[index*32+at]
    result.add(OffenderKey(key))

proc main() {.raises.} =
  ## Each declared chain starts from the same complete authored parent with explicit retained assignments.
  let raw = readFile(paramStr(1))
  var bytes = newSeq[byte](raw.len)
  for index, octet in raw: bytes[index] = byte(octet)
  let original = populationOriginal(decodeOwnedReport(bytes, 2).value)
  let retained = epoch.checkpointHex(original.stateSnapshot)
  var chain = default(ApplicationChain)
  for line in readFile(paramStr(2)).splitLines:
    if line.len == 0: continue # The final newline carries no request.
    let fields = line.splitWhitespace()
    if fields[0] == "C":
      assert fields.len == 3
      var state = forkStateStore(original.stateSnapshot).value
      let rho = epoch.unhex(fields[2])
      assert state.apply([StateWrite(key: chapterKey(StateChapter(10)), kind: StateWriteKind.Put,
          value: rho)]).error == StateStoreError.None
      let captured = captureBlockSnapshot(currentChainBytes(original.header), state.snapshot.value,
          populationParameters())
      chain = initApplicationChain(genesisView(captured)).value
      echo "P ", epoch.checkpointHex(chain.stateSnapshot.value)
    else:
      assert fields[0] == "B" or fields[0] == "N"
      assert fields.len == (if fields[0] == "B": 4 else: 5)
      let saved = epoch.checkpointHex(chain.stateSnapshot.value)
      let prior = chain.chainView.bestBlock.value
      let candidate = epoch.child(prior, number(fields[1]), @[], @[], limits = populationLimits(),
          disputeWire = epoch.unhex(fields[2]), newOffenders = offenders(fields[3]))
      let result = prepareCurrentCandidate(chain, candidate, [], populationLimits())
      if fields[0] == "N":
        assert result.error == CurrentCandidateError.PrefixFailure
        assert result.prefixFailure.error == ApplicationCandidateError.BlockFailure
        let failure = result.prefixFailure.blockFailure
        assert failure.error == BlockTransitionError.DisputesFailure
        assert $failure.disputesError == fields[4]
        assert epoch.checkpointHex(chain.stateSnapshot.value) == saved
        assert array[32, byte](chain.chainView.bestBlock.value.blockHash) == array[32, byte](
            prior.blockHash)
        echo "N ", fields[4]
      else:
        # Unexpected report failures retain their exact nested reason without changing passing corpus output.
        if result.error == CurrentCandidateError.ReportFailure:
          echo "report refusal ", result.reportFailure.error
          if result.reportFailure.error == ReportAdmissionError.PackageFailure:
            echo "package refusal ", result.reportFailure.packageError
          if result.reportFailure.error == ReportAdmissionError.AnchorFailure:
            echo "anchor refusal ", result.reportFailure.anchorError
        assert result.error == CurrentCandidateError.None, $result.error
        var wire = newSeq[byte](candidate.blockInfo.value.consumed)
        assert candidate.encodeOwnedBlock(wire).error == FrameError.None
        echo "B ", epoch.hex(wire)
        let profile = captureCurrentProfile(result.value, CurrentProfileLimits(
            validators: ElementLimit(1024), bytes: ByteLimit(65536))).value
        let globals = qualifyCurrentGlobals(profile, GlobalStateLimits(chapter: StateChapterPolicy(
            items: ElementLimit(10000), maxBytes: ByteLimit(65536)), totalBytes: ByteLimit(262144))).value
        assert qualifyCurrentState(globals, currentNamespaceServices(
            result.value.currentUpdateState, namespaceSeeds()), inventoryCaptureLimits).error ==
                CurrentStateError.None
        assert chain.canInstallPrepared(result.value)
        chain.installPrepared(result.value)
        echo "O ", epoch.checkpointHex(chain.stateSnapshot.value)
  assert epoch.checkpointHex(original.stateSnapshot) == retained

try:
  main() # A refused expected success, wrong typed failure or changed original map fails the entire corpus.
except:
  quit(2)
