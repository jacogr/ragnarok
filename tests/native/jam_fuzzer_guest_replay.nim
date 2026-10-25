# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Independently authored complete seeds and signed children execute through the actual ephemeral fuzzer backend.
import std/[assertions, cmdline, strutils, syncio]
import ../support/[fuzz_backend_context, accumulation_current_chain_context, fuzz_guest_replay_context]
import ../support/current_stf_epoch_context as epoch
import ../../src/app/[fuzz_backend, fuzz_rejection, candidate]
import ../../src/chain/[genesis, parameters]
import ../../src/codec/[bounded, block_codec, header, report_owned]
import ../../src/state/[store, checkpoint, fuzz_protocol, report_admission, report_anchors]

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
  let initialHeader = currentChainFixture(decodeOwnedReport(bytes, 2).value, ticket = true,
    completeState = true).parent.value.header
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
    if fields[0] in ["C", "A"]:
      assert not anchorChecks or not mirrorActive
      anchorChecks = fields[0] == "A"
      assert not sibling
      retainedSibling = false # Reset retires all previous chain and sibling owners.
      if seeded:
        assert epoch.checkpointHex(backend.observe(initialHeader)) == original
      config = fuzzGuestReplayConfig()
      if fields.len == 3:
        let parameters = decodeParameters(epoch.unhex(fields[2]))
        assert parameters.ok
        config.parameters = parameters.value # Trusted test-host configuration is separate from fuzz-v1 Initialize bytes.
      let captured = decodeFullCheckpoint(epoch.unhex(fields[1]), config.wire.state, ByteLimit(1000000))
      assert captured.error == CheckpointError.None
      if anchorChecks:
        config.candidate.reporting.reports.anchors.lookupAge = LookupAge(0)
      backend = initFuzzBackend(config).value
      let initialized = backend.executeFuzz(fuzzInitialize(initialHeader,
          captured.value.snapshot.value))
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
  assert seeded and not sibling and epoch.checkpointHex(backend.observe(initialHeader)) == original
try:
  main() # Missing inputs, invalid signatures, failed guests or unequal maps fail the complete registered corpus.
except:
  quit(2)
