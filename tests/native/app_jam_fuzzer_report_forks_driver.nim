# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Nonempty guarantee siblings restore original parent maps and ancestry before original-last publication.
import std/assertions
import std/cmdline
import std/strutils
import std/syncio
import ../support/state_current_stf_epoch_context as epoch
import ../support/state_current_consecutive_context
import ../support/state_accumulation_current_chain_context
import ../support/state_current_namespace_context
import ../support/state_inventory_context
import ../support/app_fuzz_backend_context
import ../../src/app/chain as app_chain
import ../../src/app/candidate as app_candidate
import ../../src/app/fuzz_backend as app_fuzz_backend
import ../../src/app/fuzz_rejection as app_fuzz_rejection
import ../../src/chain/genesis as chain_genesis
import ../../src/chain/provider as chain_provider
import ../../src/codec/bounded as codec_bounded
import ../../src/codec/report_owned as codec_report_owned
import ../../src/codec/block_codec as codec_block_codec
import ../../src/codec/header as codec_header
import ../../src/codec/state_layout as codec_state_layout
import ../../src/codec/state_composition as codec_state_composition
import ../../src/state/fuzz_protocol as state_fuzz_protocol
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

proc limits(): CurrentCandidateLimits =
  ## Six distinct reporters/assurers and two available reports have explicit resource ceilings.
  result = currentConsecutiveLimits()
  result.completion.composition.validators.projection.assurances = ElementLimit(6)
  result.completion.composition.validators.projection.reporters = ElementLimit(6)
  result.completion.composition.validators.projection.comparisons = ElementLimit(36)
  result.completion.composition.activity.available = ElementLimit(2)
  result.completion.composition.activity.assurances = ElementLimit(6)

proc reason(outcome: CurrentCandidateResult): string =
  ## Only selected typed failures grant their exact report or availability reason.
  var failure = default(ReportAdmissionResult[AdmittedReports])
  if outcome.error == CurrentCandidateError.PrefixFailure:
    let prefix = outcome.prefixFailure
    if prefix.error == ApplicationCandidateError.BlockFailure:
      let blockFailure = prefix.blockFailure
      if blockFailure.error == BlockTransitionError.AvailabilityFailure:
        let availability = blockFailure.availabilityError
        if availability.error == AvailabilityTransitionError.ContextFailure:
          return "assurance/" & $availability.contextError
        return "availability/" & $availability.error
      return "block/" & $blockFailure.error
    assert prefix.error == ApplicationCandidateError.ReportFailure
    failure = prefix.reportFailure
  elif outcome.error == CurrentCandidateError.ReportFailure:
    failure = outcome.reportFailure
  else:
    return $outcome.error # Unexpected completion/preparation failures must not match a protocol refusal.
  case failure.error
  of ReportAdmissionError.CredentialFailure: "credential/" & $failure.credentialError.error
  of ReportAdmissionError.PolicyFailure: "policy/" & $failure.policyError
  of ReportAdmissionError.AnchorFailure: "anchor/" & $failure.anchorError
  of ReportAdmissionError.PackageFailure: "package/" & $failure.packageError
  of ReportAdmissionError.AssignmentFailure: "assignment/" & $failure.assignmentError
  else: "report/" & $failure.error # No unclassified failure masquerades as a successful empty batch.

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
  var backend = default(FuzzBackend)
  var groupParent = default(BlockSnapshotResult)
  var variantHeader = default(OwnedHeader)
  var variantState = ""
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
      var config = fuzzBackendTestConfig()
      config.candidate = limits()
      config.initialAncestry = true
      config.forkStates = ElementLimit(2)
      groupParent = default(BlockSnapshotResult)
      backend = initFuzzBackend(config).value
      var unknown = default(array[32, byte])
      unknown[0] = 99
      assert backend.executeFuzz(fuzzInitialize(chain.chainView.bestBlock.value.header,
        chain.stateSnapshot.value, [FuzzAncestor(slot: HeaderSlot(0), hash: FuzzHeaderHash(
            unknown))])).error == FuzzBackendError.None
      echo "P ", epoch.checkpointHex(chain.stateSnapshot.value)
    else:
      assert fields[0] == "B" or fields[0] == "N" or fields[0] == "V"
      let selected = captureBlockSnapshot(currentChainBytes(backend.fuzzBackendHeader.value),
        backend.executeFuzz(fuzzGetState(backend.fuzzBackendHeader.value)).value.fuzzState.value,
            currentChainSettings())
      let before = if groupParent.error == GenesisError.None: groupParent.value else: selected.value
      let saved = epoch.checkpointHex(before.stateSnapshot)
      let child = currentSameEpochBodyChild(before, epoch.unhex(fields[1]))
      let response = backend.executeFuzz(fuzzImport(child))
      let outcome = if response.error == FuzzBackendError.CandidateFailure: response.candidateFailure else: default(CurrentCandidateResult)
      if fields[0] == "N":
        assert fields.len == 3
        assert response.error == FuzzBackendError.CandidateFailure
        assert reason(outcome) == fields[2], reason(outcome)
        assert consensusFuzzRejection(outcome) == (fields[2] != "anchor/MissingLookupAnchor")
        if fields[2] == "anchor/MissingLookupAnchor": assert localFuzzCandidateReason(outcome) == "MissingLookupAnchor"
        assert epoch.checkpointHex(backend.executeFuzz(fuzzGetState(
            before.header)).value.fuzzState.value) == saved
        assert array[32, byte](fuzzGetState(backend.fuzzBackendHeader.value).fuzzRequestedHeader.value) ==
            array[32, byte](before.blockHash)
        echo "N ", fields[2]
      else:
        assert fields.len == 2
        assert response.error == FuzzBackendError.None, $response.error
        var wire = newSeq[byte](child.blockInfo.value.consumed)
        assert child.encodeOwnedBlock(wire).error == FrameError.None
        echo "B ", epoch.hex(wire)
        let selected = backend.executeFuzz(fuzzGetState(
            backend.fuzzBackendHeader.value)).value.fuzzState.value
        assert array[32, byte](response.value.fuzzRoot.value) == array[32, byte](
            selected.commitment.root)
        echo "O ", epoch.checkpointHex(selected)
        if fields[0] == "V":
          groupParent = captureBlockSnapshot(currentChainBytes(before.header), before.stateSnapshot,
              currentChainSettings())
          variantHeader = backend.fuzzBackendHeader.value
          variantState = epoch.checkpointHex(selected)
          var damaged = wire
          damaged[32] = damaged[32] xor 1
          let failed = backend.executeFuzz(fuzzImport(decodeBlock(damaged, fuzzBackendTestConfig().wire.frame).value.owner))
          assert failed.error == FuzzBackendError.CandidateFailure
          assert consensusFuzzRejection(failed.candidateFailure)
          assert epoch.checkpointHex(backend.executeFuzz(fuzzGetState(
              variantHeader)).value.fuzzState.value) == variantState
          let actualHead = array[32, byte](fuzzGetState(
              backend.fuzzBackendHeader.value).fuzzRequestedHeader.value)
          let expectedHead = array[32, byte](fuzzGetState(variantHeader).fuzzRequestedHeader.value)
          assert actualHead == expectedHead
        elif groupParent.error == GenesisError.None:
          assert epoch.checkpointHex(backend.executeFuzz(fuzzGetState(
              variantHeader)).value.fuzzState.value) == variantState
          groupParent = default(BlockSnapshotResult) # Only the original-last child becomes the next group's parent.

  assert epoch.checkpointHex(original.stateSnapshot) == retained

try:
  main() # Every I/O, protocol, qualification or complete-map failure fails the whole corpus.
except:
  quit(2)
