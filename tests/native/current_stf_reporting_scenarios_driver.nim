# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Execute independently authored initial maps and signed block scenarios through genuine candidate completion and publication.
import std/[assertions, cmdline, strutils, syncio]
import ../support/current_stf_epoch_context as epoch
import ../support/[current_stf_population_context, current_stf_population_reporting_context,
  accumulation_current_chain_context, reporting_namespace_context, reporting_declarations_context, state_inventory_context]
import ../../src/app/[chain, candidate, trace_import]
import ../../src/chain/[genesis, provider, parameters]
import ../../src/codec/[bounded, report_owned, block_codec, header, state_layout, state_trie,
  state_composition]
import ../../src/state/[store, checkpoint, accumulation_current_update, current_profile,
  current_globals, current_state, global_snapshot, trace_step, trace_state]

when defined(lateRetention):
  import ../support/current_stf_late_retention_context
elif defined(rotationIncarnations):
  import ../support/current_stf_rotation_incarnations_context
elif defined(rotationRequests):
  import ../support/current_stf_rotation_requests_context
elif defined(rotationCode):
  import ../support/current_stf_rotation_code_context
elif defined(rotationLifecycle):
  import ../support/current_stf_rotation_lifecycle_context
elif defined(rotationDesignations):
  import ../support/current_stf_rotation_designation_context
elif defined(rotationHosts):
  import ../support/current_stf_rotation_hosts_context

proc scenarioLimits(): CurrentCandidateLimits =
  ## Explicit corpus build profiles keep original reporting ceilings unchanged.
  when defined(lateRetention):
    result = lateRetentionLimits()
  elif defined(rotationIncarnations):
    result = rotationIncarnationLimits()
  elif defined(rotationRequests):
    rotationRequestLimits()
  elif defined(rotationCode):
    rotationCodeLimits()
  elif defined(rotationLifecycle):
    rotationLifecycleLimits()
  elif defined(rotationDesignations):
    rotationDesignationLimits()
  elif defined(rotationHosts):
    rotationHostLimits()
  else:
    populationReportingLimits()

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

proc prepareScenarioTrace(chain: ApplicationChain, step: TraceStep, ancestors: openArray[
    OwnedHeader], wire: openArray[byte]): PreparedCurrentChainUpdate =
  ## Fully recommitted wrong maps and an altered seal must never produce installable authority or change the selected parent.
  let before = chain.chainView.bestBlock.value
  let saved = epoch.checkpointHex(before.stateSnapshot)
  template unchanged() =
    assert epoch.checkpointHex(chain.stateSnapshot.value) == saved
    assert array[32, byte](chain.chainView.bestBlock.value.blockHash) == array[32, byte](
        before.blockHash)
  let prior = step.tracePreState.value
  let posterior = step.tracePostState.value
  let child = step.traceBlock.value
  let wrongPre = newTraceStep(posterior, child, posterior, ByteLimit(16000000)).value
  assert prepareTraceImport(chain, wrongPre, ancestors, scenarioLimits()).error ==
      TraceImportError.PreStateMismatch
  unchanged()
  echo "R PreStateMismatch"
  let wrongPost = newTraceStep(prior, child, prior, ByteLimit(16000000)).value
  assert prepareTraceImport(chain, wrongPost, ancestors, scenarioLimits()).error ==
      TraceImportError.PostStateMismatch
  unchanged()
  echo "R PostStateMismatch"
  var altered = newSeq[byte](wire.len)
  for index, octet in wire: altered[index] = octet # Tampering owns a fresh buffer; the supplied signed block stays immutable.
  let headerBytes = child.blockInfo.value.headerBytes
  assert headerBytes > 0 and headerBytes <= altered.len
  altered[headerBytes-1] = altered[headerBytes-1] xor 1
  let bad = decodeBlock(altered, scenarioLimits().reporting.admission.frame)
  assert bad.error == FrameError.None and bad.value.consumed == altered.len
  let wrongSeal = newTraceStep(prior, bad.value.owner, posterior, ByteLimit(16000000)).value
  let rejected = prepareTraceImport(chain, wrongSeal, ancestors, scenarioLimits())
  assert rejected.error == TraceImportError.CandidateFailure and rejected.candidateFailure.error !=
      CurrentCandidateError.None
  unchanged()
  echo "R CandidateFailure"
  let prepared = prepareTraceImport(chain, step, ancestors, scenarioLimits())
  if prepared.error == TraceImportError.CandidateFailure:
    assert false, populationReason(prepared.candidateFailure) # Keep actual nested admission/execution diagnostics on unexpected refusal.
  assert prepared.error == TraceImportError.None
  unchanged()
  prepared.value # This certificate retains actual execution; the decoded advertised posterior remains comparison-only.

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
  var declarations: seq[DeclaredService] = @[]
  var suppliedDeclarations = false
  for line in readFile(paramStr(2)).splitLines:
    if line.len == 0: continue # The final newline is transport framing only.
    let fields = line.splitWhitespace()
    if fields[0] == "C":
      assert fields.len in [4, 5, 6]
      if originalWire.len > 0:
        assert epoch.checkpointHex(original) == originalWire # Previous chain installation cannot mutate its original owner.
      let restored = decodeFullCheckpoint(epoch.unhex(fields[3]), suppliedRoot(fields[2]), stores,
          ByteLimit(16000000))
      assert restored.error == CheckpointError.None
      original = restored.value.snapshot.value
      originalWire = epoch.checkpointHex(original)
      var configured = populationParameters()
      if fields.len >= 5:
        let decoded = decodeParameters(epoch.unhex(fields[4]))
        assert decoded.ok
        configured = decoded.value # Explicit complete trusted parameters accompany authored original inputs.
      chain = initApplicationChain(genesisView(captureBlockSnapshot(currentChainBytes(seed.header),
          original, configured))).value
      suppliedDeclarations = fields.len == 6
      declarations = @[]
      if suppliedDeclarations:
        assert fields[5].len <= 32768
        declarations = decodeDeclarations(epoch.unhex(fields[5]))
      ancestors = @[]
      echo "P ", originalWire
    else:
      assert fields[0] in ["B", "N", "S", "T"]
      let before = chain.chainView.bestBlock.value
      let saved = epoch.checkpointHex(before.stateSnapshot)
      let supplied = epoch.unhex(fields[1])
      var imported = default(TraceStep)
      var child = default(OwnedBlock)
      if fields[0] == "T":
        let frame = scenarioLimits().reporting.admission.frame
        let policy = TraceStepLimits(frame: frame, state: stores, bytes: ByteLimit(16000000))
        let decoded = decodeTraceStep(supplied, policy)
        assert decoded.error == TraceStepError.None and decoded.value.traceStepBytes.value == supplied.len
        imported = decoded.value
        child = imported.traceBlock.value
      else:
        let decoded = decodeBlock(supplied, scenarioLimits().reporting.admission.frame)
        assert decoded.error == FrameError.None and decoded.value.consumed == supplied.len
        child = decoded.value.owner
      if fields[0] == "N":
        let outcome = prepareCurrentCandidate(chain, child, ancestors, scenarioLimits())
        assert fields.len == 3 and outcome.error != CurrentCandidateError.None
        assert populationReason(outcome) == fields[2], populationReason(outcome)
        assert epoch.checkpointHex(chain.stateSnapshot.value) == saved
        assert array[32, byte](chain.chainView.bestBlock.value.blockHash) == array[32, byte](
            before.blockHash)
        echo "N ", fields[2]
      else:
        assert fields.len == (if fields[0] == "S": 3 else: 2)
        let info = child.blockInfo
        assert info.error == FrameError.None
        var wire = newSeq[byte](info.value.consumed)
        assert child.encodeOwnedBlock(wire).error == FrameError.None
        if fields[0] != "T": assert wire == supplied # Independently signed bytes are never re-signed by the native program.
        echo "B ", epoch.hex(wire)
        var update = default(PreparedCurrentChainUpdate)
        if fields[0] == "T":
          update = prepareScenarioTrace(chain, imported, ancestors, wire)
        else:
          let outcome = prepareCurrentCandidate(chain, child, ancestors, scenarioLimits())
          assert outcome.error == CurrentCandidateError.None, populationReason(outcome)
          update = outcome.value
        let profile = captureCurrentProfile(update, CurrentProfileLimits(validators: ElementLimit(
            1024), bytes: ByteLimit(65536))).value
        let globals = qualifyCurrentGlobals(profile, GlobalStateLimits(chapter: StateChapterPolicy(
            items: ElementLimit(10000), maxBytes: ByteLimit(65536)), totalBytes: ByteLimit(262144))).value
        let services = if suppliedDeclarations: declaredServices(update.currentUpdateState, declarations)
          else: reportingServices(update.currentUpdateState)
        let qualified = qualifyCurrentState(globals, services, inventoryCaptureLimits)
        if qualified.error != CurrentStateError.None:
          assert epoch.checkpointHex(chain.stateSnapshot.value) == saved
          assert array[32, byte](chain.chainView.bestBlock.value.blockHash) == array[32, byte](
              before.blockHash)
          assert false, "inventory/IncompleteNamespaces" # Rejection cannot publish an otherwise valid candidate.
        assert chain.canInstallPrepared(update)
        chain.installPrepared(update)
        assert epoch.checkpointHex(before.stateSnapshot) ==
            saved # Publishing a recreated ID cannot mutate any retained parent.
        var next = @[before.header]
        for ancestor in ancestors: next.add(ancestor) # Only actual accepted headers supply later lookup context.
        ancestors = next
        echo "O ", epoch.checkpointHex(chain.stateSnapshot.value)
        if fields[0] == "S": restoreSelected(chain, suppliedRoot(fields[2]), stores)
  assert originalWire.len > 0 and epoch.checkpointHex(original) == originalWire

try:
  main() # Every framing, authentication, exact refusal or complete-map failure fails the corpus.
except:
  quit(2)
