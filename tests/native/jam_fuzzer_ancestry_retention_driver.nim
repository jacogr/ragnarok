# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Exact retained-evidence ceilings cause local refusals without changing independently calculated whole maps.
import std/[assertions, cmdline, strutils, syncio]
import ../support/current_stf_epoch_context as epoch
import ../support/[current_consecutive_context, accumulation_current_chain_context,
  current_namespace_context, state_inventory_context, fuzz_backend_context]
import ../../src/app/[chain, candidate]
import ../../src/app/fuzz/[backend as fuzz_backend, rejection as fuzz_rejection]
import ../../src/chain/[genesis, provider]
import ../../src/codec/[bounded, report_owned, block_codec, header]
import ../../src/codec/state/[layout as state_layout, composition as state_composition]
import ../../src/state/fuzz/protocol as fuzz_protocol
import ../../src/state/store
import ../../src/state/accumulation/current/update as accumulation_current_update
import ../../src/state/current/[profile as current_profile, globals as current_globals,
    state as current_state]
import ../../src/state/global_snapshot
import ../../src/state/report/admission as report_admission
import ../../src/state/guarantee_credentials
import "../../src/state/block/transition" as block_transition
import ../../src/state/availability

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
  for line in readFile(paramStr(2)).splitLines:
    if line.len == 0: continue # Final transport newline carries no request.
    let fields = line.splitWhitespace()
    if fields[0] == "C":
      assert fields.len == 5
      var state = forkStateStore(original.stateSnapshot).value
      assert state.apply([StateWrite(key: chapterKey(StateChapter(3)), kind: StateWriteKind.Put,
          value: epoch.unhex(fields[2]))]).error == StateStoreError.None
      chain = initApplicationChain(genesisView(captureBlockSnapshot(currentChainBytes(
          original.header), state.snapshot.value, currentChainSettings()))).value
      var config = fuzzBackendTestConfig()
      config.candidate = limits()
      config.initialAncestry = true
      config.candidate.reporting.reports.ancestors.headers = ElementLimit(uint64(parseInt(fields[3])))
      config.candidate.reporting.reports.ancestors.maxBytes = ByteLimit(uint64(parseInt(fields[4])))
      backend = initFuzzBackend(config).value
      assert backend.executeFuzz(fuzzInitialize(chain.chainView.bestBlock.value.header,
        chain.stateSnapshot.value)).error == FuzzBackendError.None
      echo "P ", epoch.checkpointHex(chain.stateSnapshot.value)
    else:
      assert fields[0] == "B" or fields[0] == "N"
      let before = captureBlockSnapshot(currentChainBytes(backend.fuzzBackendHeader.value),
        backend.executeFuzz(fuzzGetState(backend.fuzzBackendHeader.value)).value.fuzzState.value,
            currentChainSettings()).value
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
  assert epoch.checkpointHex(original.stateSnapshot) == retained

try:
  main() # Every I/O, protocol, qualification or complete-map failure fails the whole corpus.
except:
  quit(2)
