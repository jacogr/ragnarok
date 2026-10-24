# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Exact independent report bodies pass genuine candidate admission, availability and complete-state publication.
import std/[assertions, cmdline, strutils, syncio]
import ../support/current_stf_epoch_context as epoch
import ../support/[current_consecutive_context, accumulation_current_chain_context,
  current_namespace_context, state_inventory_context]
import ../../src/app/[chain, candidate]
import ../../src/chain/[genesis, provider]
import ../../src/codec/[bounded, report_owned, block_codec, header, state_layout, state_composition]
import ../../src/state/[store, accumulation_current_update, current_profile, current_globals,
  current_state, global_snapshot, report_admission, guarantee_credentials, block_transition, availability]

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
      let outcome = prepareCurrentCandidate(chain, child, ancestors, limits())
      if fields[0] == "N":
        assert fields.len == 3
        assert outcome.error != CurrentCandidateError.None
        assert reason(outcome) == fields[2], reason(outcome)
        assert epoch.checkpointHex(chain.stateSnapshot.value) == saved
        assert array[32, byte](chain.chainView.bestBlock.value.blockHash) == array[32, byte](
            before.blockHash)
        echo "N ", fields[2]
      else:
        assert fields.len == 2
        assert outcome.error == CurrentCandidateError.None, reason(outcome)
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
