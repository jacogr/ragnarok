# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Actual independent siblings, original-last imports and complete states are compared with a separate mathematical reference.
import std/[assertions, cmdline, strutils, syncio]
import ../support/[fuzz_backend_context, fuzz_fork_context, accumulation_current_chain_context]
import ../../src/app/fuzz_backend
import ../../src/chain/genesis
import ../../src/codec/[bounded, header, block_codec, report_owned]
import ../../src/state/[fuzz_protocol, store, checkpoint]
proc hex(bytes: openArray[byte]): string =
  ## Preserve exact sealed bytes and complete checkpoint representations.
  result = ""
  for octet in bytes: result.add(toHex(int(octet), 2).toLowerAscii())
proc encoded(state: StateStoreSnapshot): string =
  ## Output the complete deterministic map, including empty values and unknown global keys.
  let wire = encodeFullCheckpoint(state, ByteLimit(100000))
  assert wire.error == CheckpointError.None
  hex(wire.value)
proc imported(backend: var FuzzBackend, child: OwnedBlock): StateStoreSnapshot =
  ## Only actual successful execution followed by exact-header GetState can supply this complete observation.
  var wire = newSeq[byte](child.blockInfo.value.consumed)
  assert child.encodeOwnedBlock(wire).error == FrameError.None
  echo "B ", hex(wire)
  let outcome = backend.executeFuzz(fuzzImport(child))
  assert outcome.error == FuzzBackendError.None
  let head = backend.fuzzBackendHeader.value
  let state = backend.executeFuzz(fuzzGetState(head))
  assert state.error == FuzzBackendError.None
  result = state.value.fuzzState.value
  echo "O ", encoded(result)
proc main() {.raises.} =
  ## Three independent sibling groups exercise bounded eviction, replay, failed attempts and parent-context switching.
  let raw = readFile(paramStr(1))
  var report = newSeq[byte](raw.len)
  for index, octet in raw: report[index] = byte(octet) # Keep the pinned report source unchanged.
  let fixture = currentChainFixture(decodeOwnedReport(report, 2).value, ticket = true,
      completeState = true)
  var config = fuzzBackendTestConfig()
  config.forkStates = ElementLimit(2)
  var backend = initFuzzBackend(config).value
  assert backend.executeFuzz(fuzzInitialize(fixture.parent.value.header,
      fixture.parent.value.stateSnapshot)).error == FuzzBackendError.None
  var parent = fixture.parent.value
  echo "P ", encoded(parent.stateSnapshot)
  for group in 0..<3:
    let first = fuzzSiblingChild(parent, AuthorIndex(1))
    let second = fuzzSiblingChild(parent, AuthorIndex(2))
    let original = fuzzSiblingChild(parent, AuthorIndex(0))
    let firstState = backend.imported(first)
    let secondState = backend.imported(second)
    assert encoded(firstState) != encoded(secondState) # Author statistics make these genuine distinct whole-map siblings.
    assert encoded(backend.executeFuzz(fuzzGetState(readHeader(blockHeader(
        first).value).value.owner)).value.fuzzState.value) == encoded(firstState)
    let replay = backend.imported(first)
    assert encoded(replay) == encoded(firstState)
    var damaged = newSeq[byte](original.blockInfo.value.consumed)
    assert original.encodeOwnedBlock(damaged).error == FrameError.None
    damaged[32] = damaged[32] xor 1
    let invalid = decodeBlock(damaged, config.wire.frame).value.owner
    let failed = backend.executeFuzz(fuzzImport(invalid))
    assert failed.error == FuzzBackendError.CandidateFailure
    assert encoded(backend.executeFuzz(fuzzGetState(
        backend.fuzzBackendHeader.value)).value.fuzzState.value) == encoded(firstState)
    let actual = backend.imported(original)
    assert backend.executeFuzz(fuzzGetState(readHeader(blockHeader(
        second).value).value.owner)).error == FuzzBackendError.UnknownState
    let captured = captureBlockSnapshot(currentChainBytes(backend.fuzzBackendHeader.value), actual,
        config.parameters)
    assert captured.error == GenesisError.None
    parent = captured.value # The next group extends the original, never the last imported mutant.
    if group == 2:
      let unknown = fuzzSiblingChild(fixture.parent.value, AuthorIndex(3))
      assert backend.executeFuzz(fuzzImport(unknown)).error == FuzzBackendError.UnknownParent
  assert encoded(backend.executeFuzz(fuzzGetState(
      fixture.parent.value.header)).value.fuzzState.value) == encoded(
      fixture.parent.value.stateSnapshot)
try:
  main() # A refused real import or unavailable expected state fails the entire corpus.
except:
  quit(2)
