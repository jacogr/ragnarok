# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Independently authored complete seeds and signed children execute through the actual ephemeral fuzzer backend.
import std/[assertions, cmdline, strutils, syncio]
import ../support/[fuzz_backend_context, accumulation_current_chain_context, trace_check_context]
import ../support/current_stf_epoch_context as epoch
import ../../src/app/[fuzz_backend, fuzz_rejection]
import ../../src/chain/genesis
import ../../src/codec/[bounded, block_codec, header, report_owned]
import ../../src/state/[store, checkpoint, fuzz_protocol]

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
  var config = fuzzBackendTestConfig()
  config.candidate = traceCheckTestPolicy().candidate
  config.initialAncestry = true
  config.forkStates = ElementLimit(2)
  var backend = default(FuzzBackend)
  var seeded = false
  var original = ""
  for line in readFile(paramStr(2)).splitLines:
    if line.len == 0: continue # Only the final transport newline is empty.
    let fields = line.splitWhitespace()
    assert fields.len == 2
    if fields[0] == "C":
      if seeded:
        assert epoch.checkpointHex(backend.observe(initialHeader)) == original
      let captured = decodeFullCheckpoint(epoch.unhex(fields[1]), config.wire.state, ByteLimit(1000000))
      assert captured.error == CheckpointError.None
      backend = initFuzzBackend(config).value
      let initialized = backend.executeFuzz(fuzzInitialize(initialHeader,
          captured.value.snapshot.value))
      assert initialized.error == FuzzBackendError.None
      let state = backend.observe(initialHeader)
      assert array[32, byte](initialized.value.fuzzRoot.value) == array[32, byte](
          state.commitment.root)
      original = epoch.checkpointHex(state)
      seeded = true
      echo "P ", original
    else:
      assert fields[0] == "B" and seeded # Every independently signed child belongs to an explicitly initialized chain.
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
      echo "B ", epoch.hex(encoded)
      echo "O ", epoch.checkpointHex(state)
  assert seeded and epoch.checkpointHex(backend.observe(initialHeader)) == original
try:
  main() # Missing inputs, invalid signatures, failed guests or unequal maps fail the complete registered corpus.
except:
  quit(2)
