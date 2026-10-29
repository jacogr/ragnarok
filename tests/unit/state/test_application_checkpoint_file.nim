# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"arc": "application_checkpoint_file_arc_release"}

## Single-file application envelopes preserve exact old bytes on refusal and restore only independently matched context.
import std/[assertions, syncio]
import std/posix/posix
import ../../../src/app/chain
import ../../../src/app/checkpoint/[file as checkpoint_file, codec as checkpoint_codec,
    transfer as checkpoint_transfer, identity as checkpoint_identity]
import ../../../src/chain/genesis
import ../../../src/state/[checkpoint, store]
import ../../../src/codec/bounded
import ../../../src/codec/state/trie as state_trie
import ../../../src/lib/atomic/file as atomic_file
import ../../support/[application_checkpoint_context, arc_evidence]
const FileName = "application-checkpoint-file"
proc cycle(expected: ApplicationCheckpointIdentity) =
  ## Each bounded file/read/decode activation retires all temporary byte and complete-map owners.
  let loaded = loadApplicationCheckpoint(FileName, expected, genesisStoreLimits(), ByteLimit(100000))
  assert loaded.error == ApplicationCheckpointFileError.None
  assert array[32, byte](loaded.value.snapshot.value.commitment.root) == array[32, byte](
      expected.stateRoot)
proc main() {.raises.} =
  ## Wrong/default context, limits, native paths and corrupt selected bytes never expose success or alter old data implicitly.
  var path = FileName
  defer: discard posix.unlink(path.toCString())
  let owner = checkpointFixture()
  let expected = captureApplicationCheckpointIdentity(owner).value
  let absent = default(ApplicationCheckpointIdentity)
  assert loadApplicationCheckpoint("missing-context-path", absent, genesisStoreLimits(), ByteLimit(
      1000)).identityError == ApplicationCheckpointIdentityError.Uninitialized
  assert saveApplicationCheckpoint(FileName, owner, ByteLimit(0)).error ==
      ApplicationCheckpointFileError.LimitExceeded
  let written = saveApplicationCheckpoint(FileName, owner, ByteLimit(100000))
  assert written.error == ApplicationCheckpointFileError.None and sameApplicationCheckpoint(
      written.value, expected)
  let bytes = readBoundedFile(FileName, ByteLimit(100000)).value
  assert saveApplicationCheckpoint(FileName, owner, ByteLimit(uint64(bytes.len - 1))).error ==
      ApplicationCheckpointFileError.LimitExceeded
  let wrong = captureApplicationCheckpointIdentity(checkpointFixture(
      CheckpointFixtureVariant.Profile)).value
  assert loadApplicationCheckpoint(FileName, wrong, genesisStoreLimits(), ByteLimit(
      100000)).error == ApplicationCheckpointFileError.ContextMismatch
  assert loadApplicationCheckpoint(FileName, expected, genesisStoreLimits(), ByteLimit(uint64(
      bytes.len - 1))).error == ApplicationCheckpointFileError.LimitExceeded
  assert saveApplicationCheckpoint("missing-directory/application-checkpoint", owner, ByteLimit(
      100000)).error == ApplicationCheckpointFileError.IoFailure
  var invalidPath = "abc"
  invalidPath[1] = char(0)
  assert saveApplicationCheckpoint(invalidPath, owner, ByteLimit(100000)).error ==
      ApplicationCheckpointFileError.InvalidPath
  assert readBoundedFile(FileName, ByteLimit(100000)).value == bytes
  cycle(expected)
  let before = getOccupiedMem()
  for iteration in 0..<1000:
    cycle(expected) # No file descriptor or restored map is retained between calls.
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("application_checkpoint_file", 1000, before, after)
  var damaged = bytes
  damaged[0] = damaged[0] xor 1
  assert replaceAtomicFile(FileName, damaged, ByteLimit(100000)) == AtomicFileError.None
  let invalid = loadApplicationCheckpoint(FileName, expected, genesisStoreLimits(), ByteLimit(100000))
  assert invalid.error == ApplicationCheckpointFileError.IdentityFailure and
      invalid.identityError == ApplicationCheckpointIdentityError.InvalidFormat
  assert replaceAtomicFile(FileName, bytes, ByteLimit(100000)) == AtomicFileError.None
  cycle(expected)
  echo "PASS application checkpoint files: exact atomic envelopes, independent context, typed failures and owned recovery"
try:
  main() # Fixture/native errors cannot yield a successful empty file-recovery witness.
except:
  quit(2)
