# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Actual fuzzer Initialize/ImportBlock/GetState execution emits complete maps for the independent STF oracle.
import std/[assertions, cmdline, strutils, syncio]
import ../support/[fuzz_backend_context, accumulation_current_chain_context,
    current_consecutive_context,
    current_namespace_context]
import ../../src/app/fuzz/backend as fuzz_backend
import ../../src/app/candidate
import ../../src/chain/genesis
import ../../src/codec/[bounded, header, report_owned, block_codec]
import ../../src/codec/state/trie as state_trie
import ../../src/state/fuzz/protocol as fuzz_protocol
import ../../src/state/[store, checkpoint]
proc hex(bytes: openArray[byte]): string =
  ## Preserve every wire octet for complete deterministic comparison.
  result = ""
  for octet in bytes: result.add(toHex(int(octet), 2).toLowerAscii())
proc checkpointHex(state: StateStoreSnapshot): string =
  ## A whole-map comparison includes every key/value and an independently recomputed commitment.
  let encoded = encodeFullCheckpoint(state, ByteLimit(100000))
  assert encoded.error == CheckpointError.None
  hex(encoded.value)
proc run(base: OwnedReport, populated: bool) =
  ## Use the same independent two-chain fixture as the established whole-map STF corpus.
  let seeds = if populated: namespaceSeeds() else: @[]
  let context = currentChainFixture(base, ticket = true, completeState = true,
      serviceNamespaces = seeds)
  let config = fuzzBackendTestConfig()
  var backend = initFuzzBackend(config).value
  let initialize = fuzzInitialize(context.parent.value.header, context.parent.value.stateSnapshot)
  let initialized = backend.executeFuzz(initialize)
  assert initialized.error == FuzzBackendError.None
  assert array[32, byte](initialized.value.fuzzRoot.value) == array[32, byte](
      context.parent.value.stateRoot)
  let original = backend.executeFuzz(fuzzGetState(
      context.parent.value.header)).value.fuzzState.value
  echo "P ", checkpointHex(original)
  for index in 0..<10:
    let header = backend.fuzzBackendHeader.value
    let before = backend.executeFuzz(fuzzGetState(header)).value.fuzzState.value
    let captured = captureBlockSnapshot(currentChainBytes(header), before, config.parameters)
    assert captured.error == GenesisError.None
    let child = currentEmptyChild(captured.value)
    var bytes = newSeq[byte](child.blockInfo.value.consumed)
    assert child.encodeOwnedBlock(bytes).error == FrameError.None
    echo "B ", hex(bytes)
    if index == 0:
      var wrong = bytes
      wrong[32] = wrong[32] xor 1
      let refused = decodeBlock(wrong, config.wire.frame)
      assert refused.error == FrameError.None
      let failure = backend.executeFuzz(fuzzImport(refused.value.owner))
      assert failure.error == FuzzBackendError.CandidateFailure
      assert failure.candidateFailure.error == CurrentCandidateError.PrefixFailure
      assert checkpointHex(backend.executeFuzz(fuzzGetState(header)).value.fuzzState.value) ==
          checkpointHex(before)
    let result = backend.executeFuzz(fuzzImport(child))
    assert result.error == FuzzBackendError.None
    let after = backend.executeFuzz(fuzzGetState(backend.fuzzBackendHeader.value)).value.fuzzState.value
    assert array[32, byte](result.value.fuzzRoot.value) == array[32, byte](after.commitment.root)
    assert checkpointHex(before) == checkpointHex(captured.value.stateSnapshot)
    echo "O ", checkpointHex(after)
  assert checkpointHex(backend.executeFuzz(fuzzGetState(
      context.parent.value.header)).value.fuzzState.value) == checkpointHex(original)
proc main() {.raises.} =
  ## The frozen report seeds unused service code; independently signed empty-body children exercise actual STF.
  let raw = readFile(paramStr(1))
  var bytes = newSeq[byte](raw.len)
  for index, octet in raw: bytes[index] = byte(octet) # The fixed report input is never modified.
  let base = decodeOwnedReport(bytes, 2).value
  run(base, false)
  run(base, true)
try:
  main() # I/O, owner or candidate refusal fails the entire comparison rather than emitting partial success.
except:
  quit(2)
