# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Independent population-changing report bodies exercise roster credentials, availability and complete-state publication.
import std/[assertions, cmdline, strutils, syncio]
import ../support/current_stf_epoch_context as epoch
import ../support/current_stf_reporting_context
import ../support/current_stf_population_context
import ../support/current_stf_population_reporting_context
import ../support/[current_consecutive_context, accumulation_current_chain_context,
  current_namespace_context, state_inventory_context]
import ../../src/app/[chain, candidate]
import ../../src/chain/[genesis, provider]
import ../../src/codec/[bounded, report_owned, block_codec, header, state_layout, state_composition]
import ../../src/state/[store, accumulation_current_update, current_profile, current_globals,
  current_state, global_snapshot, accumulation_current_completion, report_admission,
  guarantee_credentials, block_transition, availability]

proc main() {.raises.} =
  ## Each chain adds only the declared original recent package, then retains exact ancestral header owners.
  let raw = readFile(paramStr(1))
  var bytes = newSeq[byte](raw.len)
  for index, octet in raw: bytes[index] = byte(octet)
  let original = populationOriginal(decodeOwnedReport(bytes, 2).value)
  let retained = epoch.checkpointHex(original.stateSnapshot)
  var chain = default(ApplicationChain)
  var ancestors: seq[OwnedHeader] = @[]
  for line in readFile(paramStr(2)).splitLines:
    if line.len == 0: continue # Final transport newline carries no request.
    let fields = line.splitWhitespace()
    if fields[0] == "C":
      assert fields.len == 4
      var state = forkStateStore(original.stateSnapshot).value
      assert state.apply([StateWrite(key: chapterKey(StateChapter(3)), kind: StateWriteKind.Put,
          value: epoch.unhex(fields[2])), StateWrite(key: chapterKey(StateChapter(6)),
          kind: StateWriteKind.Put, value: epoch.unhex(fields[3]))]).error == StateStoreError.None
      chain = initApplicationChain(genesisView(captureBlockSnapshot(currentChainBytes(
          original.header), state.snapshot.value, populationParameters()))).value
      ancestors = @[]
      echo "P ", epoch.checkpointHex(chain.stateSnapshot.value)
    else:
      assert fields[0] == "B" or fields[0] == "N"
      let before = chain.chainView.bestBlock.value
      let saved = epoch.checkpointHex(before.stateSnapshot)
      let slot = uint32(parseInt(fields[1]))
      let child = epoch.child(before, slot, @[], @[], limits = populationReportingLimits(),
          bodyWire = epoch.unhex(fields[2]))
      let outcome = prepareCurrentCandidate(chain, child, ancestors, populationReportingLimits())
      if fields[0] == "N":
        assert fields.len == 4
        assert outcome.error != CurrentCandidateError.None
        assert populationReason(outcome) == fields[3], populationReason(outcome)
        assert epoch.checkpointHex(chain.stateSnapshot.value) == saved
        assert array[32, byte](chain.chainView.bestBlock.value.blockHash) == array[32, byte](
            before.blockHash)
        echo "N ", fields[3]
      else:
        assert fields.len == 3
        assert outcome.error == CurrentCandidateError.None, populationReason(outcome)
        var wire = newSeq[byte](child.blockInfo.value.consumed)
        assert child.encodeOwnedBlock(wire).error == FrameError.None
        echo "B ", epoch.hex(wire)
        let profile = captureCurrentProfile(outcome.value, CurrentProfileLimits(
            validators: ElementLimit(1024), bytes: ByteLimit(65536))).value
        let globalResult = qualifyCurrentGlobals(profile, GlobalStateLimits(
            chapter: StateChapterPolicy(items: ElementLimit(10000), maxBytes: ByteLimit(65536)),
                totalBytes: ByteLimit(262144)))
        if globalResult.error == CurrentGlobalsError.GlobalFailure:
          let failed = globalResult.globalFailure
          if failed.error == GlobalStateError.ChapterFailure:
            echo "global failure chapter ", failed.failedChapter, " reason ", failed.chapterError
        assert globalResult.error == CurrentGlobalsError.None
        let globals = globalResult.value
        assert qualifyCurrentState(globals, currentNamespaceServices(
            outcome.value.currentUpdateState, namespaceSeeds()), inventoryCaptureLimits).error ==
                CurrentStateError.None
        chain.installPrepared(outcome.value)
        var next = @[before.header]
        for ancestor in ancestors: next.add(ancestor)
        ancestors = next
        echo "O ", epoch.checkpointHex(chain.stateSnapshot.value)
  assert epoch.checkpointHex(original.stateSnapshot) == retained

try:
  main() # Every I/O, protocol, qualification or complete-map failure fails the whole corpus.
except:
  quit(2)
