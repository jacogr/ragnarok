# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Independently authored complete seeds and signed children execute through the actual ephemeral fuzzer backend.
import std/[assertions, cmdline, strutils, syncio]
import ../support/[fuzz_backend_context, accumulation_current_chain_context, fuzz_guest_replay_context]
import ../support/current_stf_epoch_context as epoch
import ../../src/app/[fuzz_backend, fuzz_rejection, candidate]
import ../../src/chain/[genesis, parameters, provider]
import ../../src/codec/[bounded, block_codec, header, report_owned]
import ../../src/state/[store, checkpoint, fuzz_protocol, report_admission, report_anchors,
    block_transition, block_admission]

proc observe(backend: var FuzzBackend, header: OwnedHeader): StateStoreSnapshot =
  ## Query exact full-header identity; no state observed from the native backend calculates an expected answer.
  let reply = backend.executeFuzz(fuzzGetState(header))
  assert reply.error == FuzzBackendError.None
  reply.value.fuzzState.value
proc main() {.raises.} =
  ## Seeds deliberately use the established initial header; imports retain genuine GP checks and atomic complete-map publication.
  let raw = readFile(paramStr(1))
  var bytes = newSeq[byte](raw.len)
  for index, octet in raw: bytes[index] = byte(octet)
  let defaultHeader = currentChainFixture(decodeOwnedReport(bytes, 2).value, ticket = true,
    completeState = true).parent.value.header
  var initialHeader = defaultHeader
  var pendingHeader = default(OwnedHeader)
  var hasHeader = false
  var pendingAncestors: seq[FuzzAncestor] = @[]
  var omitted = default(FuzzBackend)
  var testOmission = false
  var config = fuzzGuestReplayConfig()
  var backend = default(FuzzBackend)
  var seeded = false
  var original = ""
  var sibling = false
  var retainedSibling = false
  var siblingHeader = default(OwnedHeader)
  var siblingState = ""
  var anchorChecks = false
  var mirrorActive = false
  var mirror = default(FuzzBackend)
  for line in readFile(paramStr(2)).splitLines:
    if line.len == 0: continue # Only the final transport newline is empty.
    let fields = line.splitWhitespace()
    assert fields.len in [2, 3]
    if fields[0] == "H":
      assert fields.len in [2, 3] and not hasHeader
      let decoded = decodeHeader(epoch.unhex(fields[1]),
          config.candidate.reporting.reports.ancestors.header)
      assert decoded.error == HeaderError.None
      assert decoded.value.consumed == epoch.unhex(fields[1]).len
      pendingHeader = decoded.value.owner
      pendingAncestors = @[]
      if fields.len == 3:
        let slot = parseInt(fields[2])
        assert slot >= 0 and uint64(slot) <= uint64(high(uint32))
        pendingAncestors.add(FuzzAncestor(slot: HeaderSlot(uint32(slot)),
          hash: FuzzHeaderHash(array[32, byte](pendingHeader.headerInfo.value.unsigned.parent))))
      hasHeader = true
      echo line # Exact independently supplied bytes retain their own immutable header owner.
      continue
    if fields[0] in ["C", "A"]:
      assert not anchorChecks or not mirrorActive
      anchorChecks = fields[0] == "A"
      assert not sibling
      retainedSibling = false # Reset retires all previous chain and sibling owners.
      if seeded:
        assert epoch.checkpointHex(backend.observe(initialHeader)) == original
      initialHeader = if hasHeader: pendingHeader else: defaultHeader
      hasHeader = false
      config = fuzzGuestReplayConfig()
      if fields.len == 3:
        let parameters = decodeParameters(epoch.unhex(fields[2]))
        assert parameters.ok
        config.parameters = parameters.value # Trusted test-host configuration is separate from fuzz-v1 Initialize bytes.
      let captured = decodeFullCheckpoint(epoch.unhex(fields[1]), config.wire.state, ByteLimit(1000000))
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
          captured.value.snapshot.value, pendingAncestors))
      testOmission = pendingAncestors.len > 0
      if testOmission:
        omitted = initFuzzBackend(config).value
        assert omitted.executeFuzz(fuzzInitialize(initialHeader,
            captured.value.snapshot.value)).error == FuzzBackendError.None
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
            captured.value.snapshot.value)).error == FuzzBackendError.None
        mirrorActive = true
      let state = backend.observe(initialHeader)
      assert array[32, byte](initialized.value.fuzzRoot.value) == array[32, byte](
          state.commitment.root)
      original = epoch.checkpointHex(state)
      seeded = true
      echo "P ", original
    else:
      assert fields.len == 2 and fields[0] in ["B", "V"] and
          seeded # Every independently signed child belongs to an explicitly initialized chain.
      assert fields[0] != "V" or not sibling
      let wire = epoch.unhex(fields[1])
      let decoded = decodeBlock(wire, config.wire.frame)
      assert decoded.error == FrameError.None
      assert decoded.value.consumed == wire.len
      let beforeHeader = backend.fuzzBackendHeader.value
      let before = epoch.checkpointHex(backend.observe(beforeHeader))
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
              config.wire.frame).value.owner))
          assert bad.error == FuzzBackendError.CandidateFailure
          assert bad.candidateFailure.error == CurrentCandidateError.PrefixFailure
          let prefix = bad.candidateFailure.prefixFailure
          assert prefix.error == ApplicationCandidateError.BlockFailure
          let failure = prefix.blockFailure
          assert failure.error == BlockTransitionError.AdmissionFailure
          assert failure.admissionError == BlockAdmissionError.InvalidSlot
          assert epoch.checkpointHex(backend.observe(beforeHeader)) == before
          assert consensusFuzzRejection(bad.candidateFailure) # Both supplied header and state clocks remain lower bounds.
        headerBytes[96] = 4
        let ahead = decodeHeader(headerBytes, config.candidate.reporting.reports.ancestors.header).value.owner
        var future = initFuzzBackend(config).value
        assert future.executeFuzz(fuzzInitialize(ahead, state)).error == FuzzBackendError.None
        let denied = future.executeFuzz(fuzzImport(decoded.value.owner))
        assert denied.error == FuzzBackendError.CandidateFailure
        assert denied.candidateFailure.prefixFailure.blockFailure.admissionError ==
            BlockAdmissionError.InvalidSlot
        assert epoch.checkpointHex(future.observe(ahead)) ==
            before # Advancing state time alone cannot pass a later supplied header.

      var damaged = wire
      damaged[32] = damaged[32] xor 1 # A genuine invalid prior-root attempt cannot publish a partial guest result.
      let negative = backend.executeFuzz(fuzzImport(decodeBlock(damaged,
          config.wire.frame).value.owner))
      assert negative.error == FuzzBackendError.CandidateFailure
      assert consensusFuzzRejection(negative.candidateFailure)
      assert epoch.checkpointHex(backend.observe(beforeHeader)) == before
      assert array[32, byte](fuzzGetState(backend.fuzzBackendHeader.value).fuzzRequestedHeader.value) ==
        array[32, byte](fuzzGetState(beforeHeader).fuzzRequestedHeader.value)
      if retainedSibling:
        assert epoch.checkpointHex(backend.observe(siblingHeader)) == siblingState
      if mirrorActive:
        let mirrorHeader = mirror.fuzzBackendHeader.value
        let mirrorState = epoch.checkpointHex(mirror.observe(mirrorHeader))
        let strict = mirror.executeFuzz(fuzzImport(decoded.value.owner))
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
          assert epoch.checkpointHex(mirror.observe(mirrorHeader)) == mirrorState
          assert array[32, byte](fuzzGetState(mirror.fuzzBackendHeader.value).fuzzRequestedHeader.value) ==
            array[32, byte](fuzzGetState(mirrorHeader).fuzzRequestedHeader.value)
          mirrorActive = false # A genuine GP lookup-age refusal cannot publish any map or head change.
      if testOmission:
        let missing = omitted.executeFuzz(fuzzImport(decoded.value.owner))
        assert missing.error == FuzzBackendError.CandidateFailure
        assert not consensusFuzzRejection(missing.candidateFailure)
        assert localFuzzCandidateReason(missing.candidateFailure) == "MissingLookupAnchor"
        assert epoch.checkpointHex(omitted.observe(initialHeader)) == original
        testOmission = false # Initial membership must be supplied honestly; the child header alone cannot invent it.
      let imported = backend.executeFuzz(fuzzImport(decoded.value.owner))
      assert imported.error == FuzzBackendError.None, $imported.error
      let header = readHeader(blockHeader(decoded.value.owner).value).value.owner
      let state = backend.observe(header)
      assert array[32, byte](imported.value.fuzzRoot.value) == array[32, byte](
          state.commitment.root)
      assert array[32, byte](fuzzGetState(backend.fuzzBackendHeader.value).fuzzRequestedHeader.value) ==
        array[32, byte](fuzzGetState(header).fuzzRequestedHeader.value)
      var encoded = newSeq[byte](wire.len)
      assert decoded.value.owner.encodeOwnedBlock(encoded).error == FrameError.None
      if fields[0] == "V":
        assert not sibling
        sibling = true
        siblingHeader = header
        siblingState = epoch.checkpointHex(state)
        retainedSibling = true # The original-last sibling must not overwrite this independent owner.
      elif sibling:
        assert epoch.checkpointHex(backend.observe(siblingHeader)) == siblingState
        sibling = false
      elif retainedSibling:
        assert backend.executeFuzz(fuzzGetState(siblingHeader)).error ==
            FuzzBackendError.UnknownState
        retainedSibling = false # A new successful direct extension retires the old sibling group.
      echo fields[0], " ", epoch.hex(encoded)
      echo "O ", epoch.checkpointHex(state)
  assert not anchorChecks or not mirrorActive
  assert not hasHeader
  assert seeded and not sibling and epoch.checkpointHex(backend.observe(initialHeader)) == original
try:
  main() # Missing inputs, invalid signatures, failed guests or unequal maps fail the complete registered corpus.
except:
  quit(2)
