# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Execute independently authored initial maps and signed block scenarios through genuine candidate completion and publication.
import std/[assertions, cmdline, strutils, syncio]
import ../support/current_stf_epoch_context as epoch
import ../support/[current_stf_population_context, current_stf_population_reporting_context,
  accumulation_current_chain_context, reporting_namespace_context, state_inventory_context]
import ../../src/app/[chain, candidate]
import ../../src/chain/[genesis, provider]
import ../../src/codec/[bounded, report_owned, block_codec, header, state_layout, state_trie,
  state_composition]
import ../../src/state/[store, checkpoint, accumulation_current_update, current_profile,
  current_globals, current_state, global_snapshot]

proc main() {.raises.} =
  ## Only initial inputs decode from the fixture; no expected posterior supplies a production successor.
  let raw = readFile(paramStr(1))
  var bytes = newSeq[byte](raw.len)
  for index, octet in raw: bytes[index] = byte(octet)
  let seed = populationOriginal(decodeOwnedReport(bytes, 2).value)
  let stores = StateStoreLimits(trie: StateTrieLimits(items: ElementLimit(10000),
      nodes: TrieNodeLimit(200000), perValue: ByteLimit(65536), totalValueBytes: ByteLimit(
          8000000)),
      writes: ElementLimit(10000), writeValueBytes: ByteLimit(8000000))
  var chain = default(ApplicationChain)
  var ancestors: seq[OwnedHeader] = @[]
  var original = default(StateStoreSnapshot)
  var originalWire = ""
  for line in readFile(paramStr(2)).splitLines:
    if line.len == 0: continue # The final newline is transport framing only.
    let fields = line.splitWhitespace()
    if fields[0] == "C":
      assert fields.len == 4
      if originalWire.len > 0:
        assert epoch.checkpointHex(original) == originalWire # Previous chain installation cannot mutate its original owner.
      let rootBytes = epoch.unhex(fields[2])
      assert rootBytes.len == 32
      var root = default(array[32, byte])
      for index in 0..<32: root[index] = rootBytes[index]
      let restored = decodeFullCheckpoint(epoch.unhex(fields[3]), StateRoot(root), stores,
          ByteLimit(16000000))
      assert restored.error == CheckpointError.None
      original = restored.value.snapshot.value
      originalWire = epoch.checkpointHex(original)
      chain = initApplicationChain(genesisView(captureBlockSnapshot(currentChainBytes(seed.header),
          original, populationParameters()))).value
      ancestors = @[]
      echo "P ", originalWire
    else:
      assert fields[0] == "B" or fields[0] == "N"
      let before = chain.chainView.bestBlock.value
      let saved = epoch.checkpointHex(before.stateSnapshot)
      let supplied = epoch.unhex(fields[1])
      let decoded = decodeBlock(supplied, populationReportingLimits().reporting.admission.frame)
      assert decoded.error == FrameError.None and decoded.value.consumed == supplied.len
      let child = decoded.value.owner
      let outcome = prepareCurrentCandidate(chain, child, ancestors, populationReportingLimits())
      if fields[0] == "N":
        assert fields.len == 3 and outcome.error != CurrentCandidateError.None
        assert populationReason(outcome) == fields[2], populationReason(outcome)
        assert epoch.checkpointHex(chain.stateSnapshot.value) == saved
        assert array[32, byte](chain.chainView.bestBlock.value.blockHash) == array[32, byte](
            before.blockHash)
        echo "N ", fields[2]
      else:
        assert fields.len == 2 and outcome.error == CurrentCandidateError.None, populationReason(outcome)
        var wire = newSeq[byte](supplied.len)
        assert child.encodeOwnedBlock(wire).error == FrameError.None
        assert wire == supplied # Independent signed blocks enter and leave framing without native re-signing.
        echo "B ", epoch.hex(wire)
        let profile = captureCurrentProfile(outcome.value, CurrentProfileLimits(
            validators: ElementLimit(1024), bytes: ByteLimit(65536))).value
        let globals = qualifyCurrentGlobals(profile, GlobalStateLimits(chapter: StateChapterPolicy(
            items: ElementLimit(10000), maxBytes: ByteLimit(65536)), totalBytes: ByteLimit(262144))).value
        assert qualifyCurrentState(globals, reportingServices(
            outcome.value.currentUpdateState), inventoryCaptureLimits).error ==
                CurrentStateError.None
        assert chain.canInstallPrepared(outcome.value)
        chain.installPrepared(outcome.value)
        var next = @[before.header]
        for ancestor in ancestors: next.add(ancestor) # Actual accepted ancestors bind later report lookups.
        ancestors = next
        echo "O ", epoch.checkpointHex(chain.stateSnapshot.value)
  assert originalWire.len > 0 and epoch.checkpointHex(original) == originalWire

try:
  main() # Every framing, authentication, exact refusal or complete-map failure fails the corpus.
except:
  quit(2)
