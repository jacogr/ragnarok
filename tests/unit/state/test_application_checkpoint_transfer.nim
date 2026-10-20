# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"arc": "application_checkpoint_transfer_arc_release"}

## Detached envelopes preserve sole ownership, explicit moved-source reset and exact publication after source retirement.
import std/[assertions, syncio]
import std/posix/posix
import ../../../src/app/[chain, checkpoint_transfer, checkpoint_codec, checkpoint_identity]
import ../../../src/codec/bounded
import ../../../src/lib/atomic_file
import ../../support/[application_checkpoint_context, arc_evidence]
const FileName = "application-checkpoint-transfer"
proc detached(): PreparedApplicationCheckpoint {.raises.} =
  ## All originating application/map/header/history aliases retire before this sole encoded owner escapes.
  let owner = checkpointFixture()
  prepareApplicationCheckpoint(owner, ByteLimit(high(uint64)))
proc cycle(owner: ApplicationChain, expected: ApplicationCheckpointIdentity) =
  ## Transfer and destruction leave source uninitialized without freeing destination bytes early.
  var source = prepareApplicationCheckpoint(owner, ByteLimit(high(uint64)))
  var destination = move(source)
  assert source.error == ApplicationCheckpointError.Uninitialized
  assert sameApplicationCheckpoint(destination.identity, expected)
  assert destination.byteLength > 238
proc main() {.raises.} =
  ## Failed/moved/narrowed owners cannot replace a previously complete file.
  var path = FileName
  defer: discard posix.unlink(path.toCString())
  let owner = checkpointFixture()
  let expected = captureApplicationCheckpointIdentity(owner).value
  var prepared = detached()
  assert sameApplicationCheckpoint(prepared.identity, expected)
  let length = prepared.byteLength
  assert prepared.publish(FileName, ByteLimit(uint64(length))) == AtomicFileError.None
  let original = readBoundedFile(FileName, ByteLimit(uint64(length))).value
  assert original == encodeApplicationCheckpoint(owner, ByteLimit(uint64(length))).value
  assert prepared.publish(FileName, ByteLimit(uint64(length - 1))) == AtomicFileError.LimitExceeded
  var failed = prepareApplicationCheckpoint(owner, ByteLimit(0))
  assert failed.error == ApplicationCheckpointError.LimitExceeded
  assert failed.publish(FileName, ByteLimit(high(uint64))) == AtomicFileError.Uninitialized
  var moved = move(prepared)
  assert prepared.error == ApplicationCheckpointError.Uninitialized
  assert prepared.publish(FileName, ByteLimit(high(uint64))) == AtomicFileError.Uninitialized
  assert moved.publish(FileName, ByteLimit(uint64(length))) == AtomicFileError.None
  assert readBoundedFile(FileName, ByteLimit(uint64(length))).value == original
  cycle(owner, expected)
  let before = getOccupiedMem()
  for iteration in 0..<1000:
    cycle(owner, expected) # No source graph or duplicate buffer owner survives one preparation/move lifetime.
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("application_checkpoint_transfer", 1000, before, after)
  echo "PASS application checkpoint transfer: detached bytes, sole ownership, moved-source reset and exact publication"
try:
  main() # Fixture/native failures never count as a successful ownership witness.
except:
  quit(2)
