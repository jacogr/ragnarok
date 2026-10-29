# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"arc": "application_ancestor_inputs_arc_release"}

## Exact file capture is bounded and atomic; structural headers never imply ancestry authority.
import std/[assertions, syncio]
import std/posix/posix
import ../../../src/app/ancestor/inputs as ancestor_inputs
import ../../../src/app/chain
import ../../../src/chain/[genesis, provider]
import ../../../src/codec/[bounded, header]
import ../../../src/lib/atomic/file as atomic_file
import ../../support/[application_checkpoint_context, arc_evidence]

proc cycle(config: HeaderConfig, size: uint64) =
  ## Successful immutable captures and late refusals release all temporary buffers at return.
  let loaded = loadAncestorInputs(["ancestor-input-a", "ancestor-input-b"], config,
    ElementLimit(2), ByteLimit(size * 2))
  assert loaded.error == AncestorInputError.None
  assert loaded.headers.len == 2
  assert loadAncestorInputs(["ancestor-input-a", "ancestor-input-missing"], config,
    ElementLimit(2), ByteLimit(high(uint64))).fileError == AtomicFileError.IoFailure

proc main() {.raises.} =
  ## Source-owned fixture supplies a real complete sealed header and its explicit chain profile.
  let source = checkpointFixture()
  let selected = source.chainView.bestBlock.value
  var wire = newSeq[byte](selected.header.headerInfo.value.consumed)
  assert encodeOwnedHeader(selected.header, wire).error == HeaderError.None
  let size = uint64(wire.len)
  var config = HeaderConfig(cores: selected.cores, authorValidators: selected.activeValidators,
    epochSlots: selected.epochSlots, maxBytes: ByteLimit(size))
  assert replaceAtomicFile("ancestor-input-a", wire, ByteLimit(high(uint64))) ==
      AtomicFileError.None
  wire[wire.high] = wire[wire.high] xor 1 # Distinct seal bytes remain structurally valid, without establishing ancestry.
  assert replaceAtomicFile("ancestor-input-b", wire, ByteLimit(high(uint64))) ==
      AtomicFileError.None
  defer:
    discard posix.unlink("ancestor-input-a")
    discard posix.unlink("ancestor-input-b") # Fixture files retire after every observation.
  assert loadAncestorInputs([], config, ElementLimit(0), ByteLimit(0)).headers.len == 0
  assert loadAncestorInputs(["ancestor-input-missing"], config, ElementLimit(0),
    ByteLimit(0)).error == AncestorInputError.LimitExceeded
  assert loadAncestorInputs(["ancestor-input-a"], config, ElementLimit(1),
    ByteLimit(size - 1)).fileError == AtomicFileError.LimitExceeded
  assert loadAncestorInputs(["ancestor-input-a", "ancestor-input-b"], config, ElementLimit(2),
    ByteLimit(size * 2 - 1)).fileError == AtomicFileError.LimitExceeded
  let loaded = loadAncestorInputs(["ancestor-input-a", "ancestor-input-b"], config,
    ElementLimit(high(uint64)), ByteLimit(high(uint64)))
  assert loaded.error == AncestorInputError.None
  var copied = loaded.headers
  copied[0] = default(OwnedHeader)
  assert loaded.headers[0].headerInfo.error == HeaderError.None
  var captured = newSeq[byte](wire.len)
  assert encodeOwnedHeader(loaded.headers[1], captured).error == HeaderError.None
  assert captured == wire
  assert replaceAtomicFile("ancestor-input-b", @[], ByteLimit(high(uint64))) == AtomicFileError.None
  assert loaded.headers[1].headerInfo.error == HeaderError.None
  let truncated = loadAncestorInputs(["ancestor-input-a", "ancestor-input-b"], config,
    ElementLimit(2), ByteLimit(high(uint64)))
  assert truncated.error == AncestorInputError.HeaderFailure
  assert truncated.headerError == HeaderError.Truncated
  wire.add(0)
  assert replaceAtomicFile("ancestor-input-b", wire, ByteLimit(high(uint64))) ==
      AtomicFileError.None
  config.maxBytes = ByteLimit(uint64(wire.len))
  assert loadAncestorInputs(["ancestor-input-b"], config, ElementLimit(1),
    ByteLimit(high(uint64))).error == AncestorInputError.TrailingBytes
  assert loadAncestorInputs(["."], config, ElementLimit(1), ByteLimit(high(uint64))).fileError ==
    AtomicFileError.IoFailure
  assert loadAncestorInputs(["ancestor-input-a" & char(0) & "suffix"], config, ElementLimit(1),
    ByteLimit(high(uint64))).fileError == AtomicFileError.InvalidPath
  wire.setLen(wire.len - 1)
  assert replaceAtomicFile("ancestor-input-b", wire, ByteLimit(high(uint64))) ==
      AtomicFileError.None
  config.maxBytes = ByteLimit(size - 1)
  assert loadAncestorInputs(["ancestor-input-a"], config, ElementLimit(1),
    ByteLimit(high(uint64))).fileError == AtomicFileError.LimitExceeded
  config.maxBytes = ByteLimit(size)
  cycle(config, size)
  let before = getOccupiedMem()
  for iteration in 0..<1000:
    cycle(config, size) # Repeated reads/late refusals must not retain files, buffers or header owners.
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("application_ancestor_inputs", 1000, before, after)
  echo "PASS application ancestor inputs: bounded exact files, atomic refusal and detached ownership"
try:
  main() # Native/fixture exceptions remain actual failures.
except:
  quit(2)
