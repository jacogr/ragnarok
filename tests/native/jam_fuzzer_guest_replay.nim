# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Independently authored complete seeds and signed children execute through the actual ephemeral fuzzer backend.
import std/[assertions, cmdline, strutils, syncio]
import ../support/[fuzz_backend_context, accumulation_current_chain_context,
    fuzz_guest_replay_context, fuzz_full_replay_context]
import ../support/current_stf_epoch_context as epoch
import ../../src/app/[fuzz_backend, fuzz_rejection, candidate]
import ../../src/chain/[genesis, parameters, provider]
import ../../src/codec/[bounded, block_codec, header, report_owned]
import ../../src/state/[store, checkpoint, fuzz_protocol, report_admission, report_anchors,
    guarantee_credentials, block_transition, block_admission, safrole_transition, availability,
    accumulation_current_completion,
    accumulation_current_recent, accumulation_current_activity, accumulation_current_authorization,
    accumulation_current_driver, accumulation_current_round]

type
  SiblingMap = object ## One immutable header and its observed checkpoint remain paired for bounded retention checks.
    header: OwnedHeader # Full sealed identity owns its bytes independently of later publications.
    state: string # Complete exported map bytes verify retained state without borrowing mutable backend storage.

proc checkpointHex(state: StateStoreSnapshot): string =
  ## Full-profile maps exceed the tiny epoch fixture display budget; export every byte under this explicit finite ceiling.
  let encoded = encodeFullCheckpoint(state, ByteLimit(4194304))
  assert encoded.error == CheckpointError.None, $encoded.error
  epoch.hex(encoded.value)

proc observe(backend: var FuzzBackend, header: OwnedHeader): StateStoreSnapshot =
  ## Query exact full-header identity; no state observed from the native backend calculates an expected answer.
  let reply = backend.executeFuzz(fuzzGetState(header))
  assert reply.error == FuzzBackendError.None
  reply.value.fuzzState.value
proc reportRefusalReason[T](failure: ReportAdmissionResult[T]): string =
  ## Only a guarded actual credential-stage failure supplies this report rejection reason.
  if failure.error == ReportAdmissionError.CredentialFailure:
    return "credential/" & $failure.credentialError.error
  "unclassified" # Other report stages need their own explicit typed interpretation before a reference can select them.

proc refusalReason(failure: CurrentCandidateResult): string =
  ## Read only guarded actual consensus-stage causes; a default or unrelated failure cannot match a planned refusal.
  if failure.error == CurrentCandidateError.ReportFailure:
    return reportRefusalReason(failure.reportFailure)
  if failure.error != CurrentCandidateError.PrefixFailure: return "unclassified"
  let prefix = failure.prefixFailure
  if prefix.error == ApplicationCandidateError.ReportFailure:
    return reportRefusalReason(prefix.reportFailure)
  if prefix.error != ApplicationCandidateError.BlockFailure: return "unclassified"
  let blockFailure = prefix.blockFailure
  case blockFailure.error
  of BlockTransitionError.DisputesFailure:
    "dispute/" & $blockFailure.disputesError
  of BlockTransitionError.AvailabilityFailure:
    let assurance = blockFailure.availabilityError
    if assurance.error == AvailabilityTransitionError.ContextFailure:
      "assurance/" & $assurance.contextError
    else:
      "availability/" & $assurance.error # Only the actual guarded availability cause can satisfy this planned refusal.
  of BlockTransitionError.SafroleFailure:
    let safrole = blockFailure.safroleError
    case safrole.error
    of SafroleTransitionError.AdmissionFailure: "ticket/" & $safrole.admissionError
    of SafroleTransitionError.MarkerFailure: "marker/" & $safrole.markerError
    of SafroleTransitionError.AuthenticationFailure: "authentication/" &
        $safrole.authenticationError
    else: "unclassified" # Local resource/rotation/context failures never impersonate a protocol rejection.
  else: "unclassified" # Other stages must add an explicit typed interpretation before being used by a reference.

proc main() {.raises.} =
  ## Seeds deliberately use the established initial header; imports retain genuine GP checks and atomic complete-map publication.
  let raw = readFile(paramStr(1))
  var bytes = newSeq[byte](raw.len)
  for index, octet in raw: bytes[index] = byte(octet)
  let defaultHeader = currentChainFixture(decodeOwnedReport(bytes, 2).value, ticket = true,
    completeState = true).parent.value.header
  var initialHeader = defaultHeader
  var pendingHeader: seq[byte] = @[]
  var pendingParentSlot = -1
  var hasHeader = false
  var pendingAncestors: seq[FuzzAncestor] = @[]
  var omitted = default(FuzzBackend)
  var testOmission = false
  var config = fuzzGuestReplayConfig()
  var backend = default(FuzzBackend)
  var seeded = false
  var original = ""
  var sibling = false
  var savedSiblings: seq[SiblingMap] = @[]
  var anchorChecks = false
  var mirrorActive = false
  var mirror = default(FuzzBackend)
  for line in readFile(paramStr(2)).splitLines:
    if line.len == 0: continue # Only the final transport newline is empty.
    let fields = line.splitWhitespace()
    assert fields.len in [2, 3]
    if fields[0] == "H":
      assert fields.len in [2, 3] and not hasHeader
      pendingHeader = epoch.unhex(fields[1])
      pendingParentSlot = -1
      pendingAncestors = @[]
      if fields.len == 3:
        let slot = parseInt(fields[2])
        assert slot >= 0 and uint64(slot) <= uint64(high(uint32))
        pendingParentSlot = slot # Decode only after the following trusted host profile is selected.
      hasHeader = true
      echo line # Exact independently supplied bytes retain their own immutable header owner.
      continue
    if fields[0] in ["C", "A"]:
      assert not anchorChecks or not mirrorActive
      anchorChecks = fields[0] == "A"
      assert not sibling
      savedSiblings = @[] # Reset retires all previous chain and sibling owners.
      if seeded:
        assert checkpointHex(backend.observe(initialHeader)) == original
      config = fuzzGuestReplayConfig()
      if fields.len == 3:
        let parameters = decodeParameters(epoch.unhex(fields[2]))
        assert parameters.ok
        if parameters.value.get(coreCount) == 341:
          assert parameters.value.get(epochPeriod) == 600
          config = fuzzFullReplayConfig() # Explicit trusted host geometry selects finite policy before any state is decoded.
        else:
          assert parameters.value.get(coreCount) == 2 and parameters.value.get(epochPeriod) == 12
        config.parameters = parameters.value # Trusted test-host configuration is separate from fuzz-v1 Initialize bytes.
      initialHeader = defaultHeader
      if hasHeader:
        let decoded = decodeHeader(pendingHeader, config.candidate.reporting.reports.ancestors.header)
        assert decoded.error == HeaderError.None and decoded.value.consumed == pendingHeader.len
        initialHeader = decoded.value.owner
        if pendingParentSlot >= 0:
          pendingAncestors.add(FuzzAncestor(slot: HeaderSlot(uint32(pendingParentSlot)),
            hash: FuzzHeaderHash(array[32, byte](initialHeader.headerInfo.value.unsigned.parent))))
      hasHeader = false # Each explicit seed header uses its own trusted geometry, including high author indices.
      let captured = decodeFullCheckpoint(epoch.unhex(fields[1]), config.wire.state, ByteLimit(4194304))
      assert captured.error == CheckpointError.None
      var headerBytes = newSeq[byte](initialHeader.headerInfo.value.consumed)
      assert initialHeader.encodeOwnedHeader(headerBytes).error == HeaderError.None
      let marked = captureFuzzSeedSnapshot(headerBytes, captured.value.snapshot.value,
          config.parameters)
      assert marked.error == GenesisError.None and marked.value.fuzzSeedOnly
      assert genesisView(marked).bestBlock.error == GenesisError.Unavailable
      assert fuzzSeedView(marked).fuzzOnly
      var ordinaryHeader = newSeq[byte](defaultHeader.headerInfo.value.consumed)
      assert defaultHeader.encodeOwnedHeader(ordinaryHeader).error == HeaderError.None
      let ordinary = captureBlockSnapshot(ordinaryHeader, captured.value.snapshot.value,
          config.parameters)
      if ordinary.error == GenesisError.None:
        assert genesisView(ordinary).advanceView(marked).error == ViewAdvanceError.InvalidSnapshot
      if anchorChecks:
        config.candidate.reporting.reports.anchors.lookupAge = LookupAge(0)
      backend = initFuzzBackend(config).value
      let initialized = backend.executeFuzz(fuzzInitialize(initialHeader,
          captured.value.snapshot.value, pendingAncestors, config.wire))
      testOmission = pendingAncestors.len > 0
      if testOmission:
        omitted = initFuzzBackend(config).value
        assert omitted.executeFuzz(fuzzInitialize(initialHeader,
            captured.value.snapshot.value, limits = config.wire)).error == FuzzBackendError.None
      pendingAncestors = @[]
      assert initialized.error == FuzzBackendError.None
      if anchorChecks:
        var strict = config
        var parameters = config.parameters.encodeParameters
        for index in 74..<78: parameters[index] = 0 # The explicit zero-age GP profile rejects any prior lookup anchor.
        strict.parameters = decodeParameters(parameters).value
        strict.candidate.reporting.reports.anchors.lookupAge = LookupAge(14400)
        mirror = initFuzzBackend(strict).value
        assert mirror.executeFuzz(fuzzInitialize(initialHeader,
            captured.value.snapshot.value, limits = config.wire)).error == FuzzBackendError.None
        mirrorActive = true
      let state = backend.observe(initialHeader)
      assert array[32, byte](initialized.value.fuzzRoot.value) == array[32, byte](
          state.commitment.root)
      original = checkpointHex(state)
      seeded = true
      echo "P ", original
    else:
      assert ((fields.len == 2 and fields[0] in ["B", "V"]) or
          (fields.len == 3 and fields[0] == "R")) and
              seeded # Every independently signed child belongs to an explicitly initialized chain.
      let wire = epoch.unhex(fields[1])
      let decoded = decodeBlock(wire, config.wire.frame)
      assert decoded.error == FrameError.None
      assert decoded.value.consumed == wire.len
      let beforeHeader = backend.fuzzBackendHeader.value
      let before = checkpointHex(backend.observe(beforeHeader))
      if beforeHeader.headerInfo.value.unsigned.slot == HeaderSlot(0):
        let state = backend.observe(beforeHeader)
        var headerBytes = newSeq[byte](beforeHeader.headerInfo.value.consumed)
        assert beforeHeader.encodeOwnedHeader(headerBytes).error == HeaderError.None
        assert captureBlockSnapshot(headerBytes, state, config.parameters).error ==
            GenesisError.Invalid
        for slot in [0'u32, 1'u32]:
          var invalid = wire
          for index in 0..<4: invalid[96+index] = byte((slot shr (index*8)) and 255)
          let bad = backend.executeFuzz(fuzzImport(decodeBlock(invalid,
              config.wire.frame).value.owner, config.wire))
          assert bad.error == FuzzBackendError.CandidateFailure
          assert bad.candidateFailure.error == CurrentCandidateError.PrefixFailure
          let prefix = bad.candidateFailure.prefixFailure
          assert prefix.error == ApplicationCandidateError.BlockFailure
          let failure = prefix.blockFailure
          assert failure.error == BlockTransitionError.AdmissionFailure
          assert failure.admissionError == BlockAdmissionError.InvalidSlot
          assert checkpointHex(backend.observe(beforeHeader)) == before
          assert consensusFuzzRejection(bad.candidateFailure) # Both supplied header and state clocks remain lower bounds.
        headerBytes[96] = 4
        let ahead = decodeHeader(headerBytes, config.candidate.reporting.reports.ancestors.header).value.owner
        var future = initFuzzBackend(config).value
        assert future.executeFuzz(fuzzInitialize(ahead, state, limits = config.wire)).error ==
            FuzzBackendError.None
        let denied = future.executeFuzz(fuzzImport(decoded.value.owner, config.wire))
        assert denied.error == FuzzBackendError.CandidateFailure
        assert denied.candidateFailure.prefixFailure.blockFailure.admissionError ==
            BlockAdmissionError.InvalidSlot
        assert checkpointHex(future.observe(ahead)) ==
            before # Advancing state time alone cannot pass a later supplied header.

      if fields[0] == "R":
        let refused = backend.executeFuzz(fuzzImport(decoded.value.owner, config.wire))
        assert refused.error == FuzzBackendError.CandidateFailure
        assert consensusFuzzRejection(refused.candidateFailure)
        assert refusalReason(refused.candidateFailure) == fields[2], refusalReason(
            refused.candidateFailure)
        assert checkpointHex(backend.observe(beforeHeader)) == before
        assert array[32, byte](fuzzGetState(backend.fuzzBackendHeader.value).fuzzRequestedHeader.value) ==
          array[32, byte](fuzzGetState(beforeHeader).fuzzRequestedHeader.value)
        for saved in savedSiblings:
          assert checkpointHex(backend.observe(saved.header)) ==
              saved.state # Refused tickets preserve all retained variants too.
        echo line
        echo "O ", before
        continue # A rejected signed input has no posterior header, entropy, statistics or partial accumulator.
      var damaged = wire
      damaged[32] = damaged[32] xor 1 # A genuine invalid prior-root attempt cannot publish a partial guest result.
      let negative = backend.executeFuzz(fuzzImport(decodeBlock(damaged,
          config.wire.frame).value.owner, config.wire))
      assert negative.error == FuzzBackendError.CandidateFailure
      assert consensusFuzzRejection(negative.candidateFailure)
      assert checkpointHex(backend.observe(beforeHeader)) == before
      assert array[32, byte](fuzzGetState(backend.fuzzBackendHeader.value).fuzzRequestedHeader.value) ==
        array[32, byte](fuzzGetState(beforeHeader).fuzzRequestedHeader.value)
      for saved in savedSiblings:
        assert checkpointHex(backend.observe(saved.header)) ==
            saved.state # Failed candidates preserve every retained sibling.
      if mirrorActive:
        let mirrorHeader = mirror.fuzzBackendHeader.value
        let mirrorState = checkpointHex(mirror.observe(mirrorHeader))
        let strict = mirror.executeFuzz(fuzzImport(decoded.value.owner, config.wire))
        if strict.error != FuzzBackendError.None:
          assert strict.error == FuzzBackendError.CandidateFailure
          let outcome = strict.candidateFailure
          assert outcome.error == CurrentCandidateError.PrefixFailure, "zero-age candidate: " & $outcome.error
          let prefix = outcome.prefixFailure
          assert prefix.error == ApplicationCandidateError.ReportFailure, "zero-age prefix: " & $prefix.error
          let report = prefix.reportFailure
          assert report.error == ReportAdmissionError.AnchorFailure, "zero-age report: " & $report.error
          assert report.anchorError == ReportAnchorError.LookupTooOld, "zero-age anchor: " &
              $report.anchorError
          assert consensusFuzzRejection(outcome)
          assert checkpointHex(mirror.observe(mirrorHeader)) == mirrorState
          assert array[32, byte](fuzzGetState(mirror.fuzzBackendHeader.value).fuzzRequestedHeader.value) ==
            array[32, byte](fuzzGetState(mirrorHeader).fuzzRequestedHeader.value)
          mirrorActive = false # A genuine GP lookup-age refusal cannot publish any map or head change.
      if testOmission:
        let missing = omitted.executeFuzz(fuzzImport(decoded.value.owner, config.wire))
        assert missing.error == FuzzBackendError.CandidateFailure
        assert not consensusFuzzRejection(missing.candidateFailure)
        assert localFuzzCandidateReason(missing.candidateFailure) == "MissingLookupAnchor"
        assert checkpointHex(omitted.observe(initialHeader)) == original
        testOmission = false # Initial membership must be supplied honestly; the child header alone cannot invent it.
      let imported = backend.executeFuzz(fuzzImport(decoded.value.owner, config.wire))
      var diagnostic = $imported.error
      if imported.error == FuzzBackendError.CandidateFailure:
        let failed = imported.candidateFailure
        diagnostic.add(":" & $failed.error) # Test diagnostics preserve only guarded actual phase reasons.
        if failed.error == CurrentCandidateError.PrefixFailure:
          let prefix = failed.prefixFailure
          diagnostic.add(":" & $prefix.error)
          if prefix.error == ApplicationCandidateError.BlockFailure:
            let blockFailure = prefix.blockFailure
            diagnostic.add(":" & $blockFailure.error)
            if blockFailure.error == BlockTransitionError.AdmissionFailure:
              diagnostic.add(":" & $blockFailure.admissionError) # Exact commitment/framing refusal stays guarded.
            elif blockFailure.error == BlockTransitionError.SafroleFailure:
              let safrole = blockFailure.safroleError
              diagnostic.add(":" & $safrole.error)
              if safrole.error == SafroleTransitionError.AuthenticationFailure:
                diagnostic.add(":" & $safrole.authenticationError) # Distinguish author selection, seal and entropy.
              elif safrole.error == SafroleTransitionError.MarkerFailure:
                diagnostic.add(":" & $safrole.markerError) # Variable epoch-marker failures retain their typed cause.
        elif failed.error == CurrentCandidateError.CompletionFailure:
          let completion = failed.completionFailure
          diagnostic.add(":" & $completion.error)
          if completion.error == CurrentAccumulationCompletionError.RecentFailure:
            diagnostic.add(":" & $completion.recentFailure.error) # Preserve the actual history-policy/encoding stage cause.
          elif completion.error == CurrentAccumulationCompletionError.ActivityFailure:
            let activity = completion.activityFailure
            diagnostic.add(":" & $activity.error)
            if activity.error == CurrentAccumulationActivityError.CoreFailure:
              diagnostic.add(":" & $activity.coreError) # Guard nested projection causes instead of guessing a resource failure.
          elif completion.error == CurrentAccumulationCompletionError.AuthorizationFailure:
            diagnostic.add(":" & $completion.authorizationFailure.error) # Typed publication-policy failures keep their actual cause.
          elif completion.error == CurrentAccumulationCompletionError.SequenceFailure:
            let sequence = completion.sequenceFailure
            diagnostic.add(":" & $sequence.error)
            if sequence.error == CurrentSequenceDriverError.InitialFailure:
              diagnostic.add(":" & $sequence.initialFailure.error)
        elif failed.error == CurrentCandidateError.ReportFailure:
          diagnostic.add(":" & $failed.reportFailure.error)
      assert imported.error == FuzzBackendError.None, diagnostic
      let header = readHeader(blockHeader(decoded.value.owner).value).value.owner
      let state = backend.observe(header)
      assert array[32, byte](imported.value.fuzzRoot.value) == array[32, byte](
          state.commitment.root)
      assert array[32, byte](fuzzGetState(backend.fuzzBackendHeader.value).fuzzRequestedHeader.value) ==
        array[32, byte](fuzzGetState(header).fuzzRequestedHeader.value)
      var encoded = newSeq[byte](wire.len)
      assert decoded.value.owner.encodeOwnedBlock(encoded).error == FrameError.None
      if fields[0] == "V":
        if not sibling:
          # A first variant can itself directly extend the previous original-last head and retire its old group.
          for saved in savedSiblings:
            assert backend.executeFuzz(fuzzGetState(saved.header)).error ==
                FuzzBackendError.UnknownState
          savedSiblings = @[]
        sibling = true
        savedSiblings.add(SiblingMap(header: header, state: checkpointHex(state)))
        if uint64(savedSiblings.len) > uint64(config.forkStates):
          let evicted = savedSiblings[0].header
          var retained: seq[SiblingMap] = @[]
          # Retain every newer immutable owner while dropping only the oldest pair.
          for index in 1..<savedSiblings.len: retained.add(savedSiblings[index])
          savedSiblings = retained
          assert backend.executeFuzz(fuzzGetState(evicted)).error ==
              FuzzBackendError.UnknownState # The oldest map alone leaves the full window.
      elif sibling:
        if uint64(savedSiblings.len) == uint64(config.forkStates):
          let evicted = savedSiblings[0].header
          var retained: seq[SiblingMap] = @[]
          # Retain every newer immutable owner while dropping only the oldest pair.
          for index in 1..<savedSiblings.len: retained.add(savedSiblings[index])
          savedSiblings = retained
          assert backend.executeFuzz(fuzzGetState(evicted)).error ==
              FuzzBackendError.UnknownState # Original-last publication consumes its own window position.
        for saved in savedSiblings:
          assert checkpointHex(backend.observe(saved.header)) == saved.state
        sibling = false
      elif savedSiblings.len > 0:
        for saved in savedSiblings:
          assert backend.executeFuzz(fuzzGetState(saved.header)).error ==
              FuzzBackendError.UnknownState
        savedSiblings = @[] # A successful direct extension retires the complete old sibling group.
      echo fields[0], " ", epoch.hex(encoded)
      echo "O ", checkpointHex(state)
  assert not anchorChecks or not mirrorActive
  assert not hasHeader
  assert seeded and not sibling and checkpointHex(backend.observe(initialHeader)) == original
try:
  main() # Missing inputs, invalid signatures, failed guests or unequal maps fail the complete registered corpus.
except:
  quit(2)
