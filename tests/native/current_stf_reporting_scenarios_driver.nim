# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Execute independently authored initial maps and signed block scenarios through genuine candidate completion and publication.
import std/[assertions, cmdline, strutils, syncio]
import ../support/current_stf_epoch_context as epoch
import ../support/[current_stf_population_context, current_stf_population_reporting_context,
  accumulation_current_chain_context, reporting_namespace_context, state_inventory_context]
import ../../src/app/[chain, candidate]
import ../../src/chain/[genesis, provider, parameters]
import ../../src/codec/[bounded, report_owned, block_codec, header, state_layout, state_trie,
  state_composition]
import ../../src/state/[store, checkpoint, accumulation_current_update, current_profile,
  current_globals, current_state, global_snapshot]

proc suppliedRoot(text: string): StateRoot =
  ## Trusted independently authored roots have one complete fixed32-byte representation.
  let bytes = epoch.unhex(text)
  assert bytes.len == 32
  var root = default(array[32, byte])
  for index in 0..<32: root[index] = bytes[index]
  StateRoot(root)

proc restoreSelected(chain: var ApplicationChain, expected: StateRoot, policy: StateStoreLimits) =
  ## Reconstruct the actual selected state under an external expected root and recapture its exact header/configuration.
  let selected = chain.chainView.bestBlock.value
  let saved = epoch.checkpointHex(selected.stateSnapshot)
  let encoded = encodeFullCheckpoint(selected.stateSnapshot, ByteLimit(16000000))
  assert encoded.error == CheckpointError.None and encoded.value.len > 0
  var wrong = array[32, byte](expected)
  wrong[0] = wrong[0] xor 1
  assert decodeFullCheckpoint(encoded.value, StateRoot(wrong), policy, ByteLimit(16000000)).error ==
      CheckpointError.RootMismatch
  echo "K RootMismatch"
  assert decodeFullCheckpoint(encoded.value, expected, policy, ByteLimit(
      encoded.value.len-1)).error == CheckpointError.LimitExceeded
  echo "K LimitExceeded"
  assert epoch.checkpointHex(chain.stateSnapshot.value) == saved
  let restored = decodeFullCheckpoint(encoded.value, expected, policy, ByteLimit(16000000))
  assert restored.error == CheckpointError.None
  assert sameStateStorePolicy(selected.stateSnapshot, restored.value.snapshot.value)
  let captured = captureBlockSnapshot(currentChainBytes(selected.header),
      restored.value.snapshot.value, selected.chainParameters)
  assert captured.error == GenesisError.None
  let view = genesisView(captured).finalizeView(captured.value.blockHash)
  assert view.error == ViewFinalizeError.None
  let reopened = initApplicationChain(view.value)
  assert reopened.error == ApplicationChainError.None
  chain = reopened.value
  assert epoch.checkpointHex(chain.stateSnapshot.value) == saved
  assert array[32, byte](chain.chainView.bestBlock.value.blockHash) == array[32, byte](
      selected.blockHash)
  assert chain.chainView.bestBlock.value.chainParameters.encodeParameters ==
      selected.chainParameters.encodeParameters
  echo "K Restored"

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
      assert fields.len in [4, 5]
      if originalWire.len > 0:
        assert epoch.checkpointHex(original) == originalWire # Previous chain installation cannot mutate its original owner.
      let restored = decodeFullCheckpoint(epoch.unhex(fields[3]), suppliedRoot(fields[2]), stores,
          ByteLimit(16000000))
      assert restored.error == CheckpointError.None
      original = restored.value.snapshot.value
      originalWire = epoch.checkpointHex(original)
      var configured = populationParameters()
      if fields.len == 5:
        let decoded = decodeParameters(epoch.unhex(fields[4]))
        assert decoded.ok
        configured = decoded.value # Explicit complete trusted parameters accompany authored original inputs.
      chain = initApplicationChain(genesisView(captureBlockSnapshot(currentChainBytes(seed.header),
          original, configured))).value
      ancestors = @[]
      echo "P ", originalWire
    else:
      assert fields[0] in ["B", "N", "S"]
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
        assert fields.len == (if fields[0] == "S": 3 else: 2) and outcome.error ==
            CurrentCandidateError.None, populationReason(outcome)
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
        if fields[0] == "S": restoreSelected(chain, suppliedRoot(fields[2]),
            stores) # Actual ancestor owners remain separately retained, never decoded from expected posteriors.
  assert originalWire.len > 0 and epoch.checkpointHex(original) == originalWire

try:
  main() # Every framing, authentication, exact refusal or complete-map failure fails the corpus.
except:
  quit(2)
