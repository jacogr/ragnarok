# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Exact independent report bodies pass genuine candidate admission, availability and complete-state publication.
import std/assertions
import std/cmdline
import std/strutils
import std/syncio
import ../support/state_current_stf_epoch_context as epoch
import ../support/state_current_stf_reporting_context
import ../support/state_current_consecutive_context
import ../support/state_accumulation_current_chain_context
import ../support/state_current_namespace_context
import ../support/state_inventory_context
import ../../src/app/chain as app_chain
import ../../src/app/candidate as app_candidate
import ../../src/chain/genesis as chain_genesis
import ../../src/chain/provider as chain_provider
import ../../src/codec/bounded as codec_bounded
import ../../src/codec/report_owned as codec_report_owned
import ../../src/codec/block_codec as codec_block_codec
import ../../src/codec/header as codec_header
import ../../src/codec/state_layout as codec_state_layout
import ../../src/codec/state_composition as codec_state_composition
import ../../src/state/store as state_store
import ../../src/state/accumulation_current_update as state_accumulation_current_update
import ../../src/state/current_profile as state_current_profile
import ../../src/state/current_globals as state_current_globals
import ../../src/state/current_state as state_current_state
import ../../src/state/global_snapshot as state_global_snapshot
import ../../src/state/report_admission as state_report_admission
import ../../src/state/guarantee_credentials as state_guarantee_credentials
import ../../src/state/block_transition as state_block_transition
import ../../src/state/availability as state_availability

proc main() {.raises.} =
  ## Each chain adds only the declared original recent package, then retains exact ancestral header owners.
  let raw = readFile(paramStr(1))
  var bytes = newSeq[byte](raw.len)
  for index, octet in raw: bytes[index] = byte(octet)
  let seed = currentChainFixture(decodeOwnedReport(bytes, 2).value, ticket = true,
      completeState = true, serviceNamespaces = namespaceSeeds())
  let original = seed.parent.value
  let retained = epoch.checkpointHex(original.stateSnapshot)
  var chain = default(ApplicationChain)
  var ancestors: seq[OwnedHeader] = @[]
  for line in readFile(paramStr(2)).splitLines:
    if line.len == 0: continue # Final transport newline carries no request.
    let fields = line.splitWhitespace()
    if fields[0] == "C":
      assert fields.len == 3
      var state = forkStateStore(original.stateSnapshot).value
      assert state.apply([StateWrite(key: chapterKey(StateChapter(3)), kind: StateWriteKind.Put,
          value: epoch.unhex(fields[2]))]).error == StateStoreError.None
      chain = initApplicationChain(genesisView(captureBlockSnapshot(currentChainBytes(
          original.header), state.snapshot.value, currentChainSettings()))).value
      ancestors = @[]
      echo "P ", epoch.checkpointHex(chain.stateSnapshot.value)
    else:
      assert fields[0] == "B" or fields[0] == "N"
      let before = chain.chainView.bestBlock.value
      let saved = epoch.checkpointHex(before.stateSnapshot)
      let child = currentSameEpochBodyChild(before, epoch.unhex(fields[1]))
      let outcome = prepareCurrentCandidate(chain, child, ancestors, reportingLimits())
      if fields[0] == "N":
        assert fields.len == 3
        assert outcome.error != CurrentCandidateError.None
        assert reportingReason(outcome) == fields[2], reportingReason(outcome)
        assert epoch.checkpointHex(chain.stateSnapshot.value) == saved
        assert array[32, byte](chain.chainView.bestBlock.value.blockHash) == array[32, byte](
            before.blockHash)
        echo "N ", fields[2]
      else:
        assert fields.len == 2
        assert outcome.error == CurrentCandidateError.None, reportingReason(outcome)
        var wire = newSeq[byte](child.blockInfo.value.consumed)
        assert child.encodeOwnedBlock(wire).error == FrameError.None
        echo "B ", epoch.hex(wire)
        let profile = captureCurrentProfile(outcome.value, CurrentProfileLimits(
            validators: ElementLimit(1024), bytes: ByteLimit(65536))).value
        let globals = qualifyCurrentGlobals(profile, GlobalStateLimits(chapter: StateChapterPolicy(
            items: ElementLimit(10000), maxBytes: ByteLimit(65536)), totalBytes: ByteLimit(262144))).value
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
