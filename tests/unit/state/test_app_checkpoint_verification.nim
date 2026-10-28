# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"arc": "application_checkpoint_verification_arc_release"}

## Verification-only receipts preserve complete format/context checks while retiring every restored map on its allocating thread.
import std/assertions
import std/syncio
import std/posix/posix
import ../../../src/app/chain as app_chain
import ../../../src/app/checkpoint_file as app_checkpoint_file
import ../../../src/app/checkpoint_writer as app_checkpoint_writer
import ../../../src/app/checkpoint_identity as app_checkpoint_identity
import ../../../src/state/store as state_store
import ../../../src/chain/genesis as chain_genesis
import ../../../src/codec/bounded as codec_bounded
import ../../../src/lib/atomic_file as lib_atomic_file
import ../../support/app_checkpoint_context
import ../../support/testing_arc_evidence
const FileName = "application-checkpoint-verification"
proc cycle(writer: var ApplicationCheckpointWriter, expected: ApplicationCheckpointIdentity) =
  ## Alternating locked/path verification exposes fixed context and releases all temporary complete maps.
  let first = writer.verify(expected, genesisStoreLimits(), ByteLimit(100000))
  assert first.error == ApplicationCheckpointFileError.None
  assert sameApplicationCheckpoint(first.value, expected)
  let second = verifyApplicationCheckpoint(FileName, expected, genesisStoreLimits(), ByteLimit(100000))
  assert second.error == ApplicationCheckpointFileError.None
  assert sameApplicationCheckpoint(second.value, expected)
proc main() {.raises.} =
  ## Missing/default context, file/map limits, corruption and context mismatch never authorize a scalar success receipt.
  defer:
    for suffix in ["", ".lock"]:
      var path = FileName & suffix
      discard posix.unlink(path.toCString()) # Explicit close below precedes test-only lock cleanup.
  let owner = checkpointFixture()
  let expected = captureApplicationCheckpointIdentity(owner).value
  let absent = default(ApplicationCheckpointIdentity)
  assert verifyApplicationCheckpoint("missing-file", absent, genesisStoreLimits(), ByteLimit(
      100000)).identityError == ApplicationCheckpointIdentityError.Uninitialized
  assert saveApplicationCheckpoint(FileName, owner, ByteLimit(100000)).error ==
      ApplicationCheckpointFileError.None
  let bytes = readBoundedFile(FileName, ByteLimit(100000)).value
  assert verifyApplicationCheckpoint(FileName, expected, genesisStoreLimits(), ByteLimit(uint64(
      bytes.len))).error == ApplicationCheckpointFileError.None
  assert verifyApplicationCheckpoint(FileName, expected, genesisStoreLimits(), ByteLimit(uint64(
      bytes.len - 1))).error == ApplicationCheckpointFileError.LimitExceeded
  let wrong = captureApplicationCheckpointIdentity(checkpointFixture(
      CheckpointFixtureVariant.Profile)).value
  assert verifyApplicationCheckpoint(FileName, wrong, default(StateStoreLimits), ByteLimit(
      100000)).error == ApplicationCheckpointFileError.ContextMismatch
  assert verifyApplicationCheckpoint(FileName, expected, default(StateStoreLimits), ByteLimit(
      100000)).error == ApplicationCheckpointFileError.LimitExceeded
  var writer = default(ApplicationCheckpointWriter)
  defer: discard writer.close()
  assert writer.verify(expected, genesisStoreLimits(), ByteLimit(100000)).error ==
      ApplicationCheckpointFileError.Uninitialized
  assert writer.openApplicationCheckpointWriter(FileName) == ApplicationCheckpointFileError.None
  cycle(writer, expected)
  let before = getOccupiedMem()
  for iteration in 0..<1000:
    cycle(writer, expected) # Each path verifies and retires a complete decoded graph before observation.
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("app_checkpoint_verification", 1000, before, after)
  assert writer.close() == ApplicationCheckpointFileError.None
  var damaged = bytes
  damaged[0] = damaged[0] xor 1
  assert replaceAtomicFile(FileName, damaged, ByteLimit(100000)) == AtomicFileError.None
  assert verifyApplicationCheckpoint(FileName, expected, genesisStoreLimits(), ByteLimit(
      100000)).identityError == ApplicationCheckpointIdentityError.InvalidFormat
  assert readBoundedFile(FileName, ByteLimit(100000)).value ==
      damaged # Verification never repairs or republishes bytes implicitly.
  echo "PASS application checkpoint verification: fixed context receipts, complete checks and local decoded-owner retirement"
try:
  main() # Fixture/native setup errors remain failures.
except:
  quit(2)
