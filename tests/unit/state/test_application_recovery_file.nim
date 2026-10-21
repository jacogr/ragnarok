# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"arc": "application_recovery_file_arc_release"}

## Startup recovery reads exactly one selected bounded envelope and never repairs or modifies it.
import std/[assertions, syncio]
import std/posix/posix
import ../../../src/app/[chain, checkpoint_identity, checkpoint_codec, checkpoint_file, checkpoint_recovery]
import ../../../src/chain/[genesis, provider]
import ../../../src/codec/[bounded, header]
import ../../../src/state/store
import ../../../src/lib/atomic_file
import ../../support/[application_checkpoint_context, arc_evidence]
const PathName = "application-recovery-file"
proc cycle(wire: seq[byte], expected: ApplicationCheckpointIdentity) =
  ## Each read and complete restored graph retires on the startup thread.
  let owner = loadRecoveryCheckpoint(PathName, wire, expected, genesisStoreLimits(), ByteLimit(100000)).value
  assert sameApplicationCheckpoint(captureApplicationCheckpointIdentity(owner).value, expected)
  assert owner.chainView.retainedCount == 1
  assert owner.chainView.finalizedBlock.error != GenesisError.None
proc main() {.raises.} =
  ## Native failures and malformed/context-mismatched files cannot authorize a partial application.
  var path = PathName
  defer: discard posix.unlink(path.toCString())
  let source = checkpointFixture()
  let expected = captureApplicationCheckpointIdentity(source).value
  let header = source.chainView.bestBlock.value.header
  var wire = newSeq[byte](header.headerInfo.value.consumed)
  assert encodeOwnedHeader(header, wire).error == HeaderError.None
  assert loadRecoveryCheckpoint("missing", [], default(ApplicationCheckpointIdentity), default(
      StateStoreLimits), ByteLimit(0)).error == ApplicationRecoveryError.MissingTrust
  assert loadRecoveryCheckpoint("missing", wire, expected, genesisStoreLimits(), ByteLimit(
      100000)).fileFailure.error == ApplicationCheckpointFileError.IoFailure
  assert loadRecoveryCheckpoint("", wire, expected, genesisStoreLimits(), ByteLimit(
      100000)).fileFailure.error == ApplicationCheckpointFileError.InvalidPath
  assert saveApplicationCheckpoint(PathName, source, ByteLimit(100000)).error ==
      ApplicationCheckpointFileError.None
  let bytes = readBoundedFile(PathName, ByteLimit(100000)).value
  let tight = loadRecoveryCheckpoint(PathName, wire, expected, genesisStoreLimits(), ByteLimit(
      uint64(bytes.len - 1)))
  assert tight.fileFailure.error == ApplicationCheckpointFileError.LimitExceeded
  assert loadRecoveryCheckpoint(PathName, wire, expected, default(StateStoreLimits), ByteLimit(
      100000)).fileFailure.error == ApplicationCheckpointFileError.LimitExceeded
  let wrong = captureApplicationCheckpointIdentity(checkpointFixture(
      CheckpointFixtureVariant.Header)).value
  assert loadRecoveryCheckpoint(PathName, wire, wrong, genesisStoreLimits(), ByteLimit(
      100000)).fileFailure.error == ApplicationCheckpointFileError.ContextMismatch
  var wrongWire = wire
  wrongWire[wrongWire.high] = wrongWire[wrongWire.high] xor 1
  assert loadRecoveryCheckpoint(PathName, wrongWire, expected, genesisStoreLimits(), ByteLimit(
      100000)).error == ApplicationRecoveryError.HeaderMismatch
  cycle(wire, expected)
  let before = getOccupiedMem()
  for iteration in 0..<1000:
    cycle(wire, expected) # Complete maps and descriptors must not accumulate across startup attempts.
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("application_recovery_file", 1000, before, after)
  assert readBoundedFile(PathName, ByteLimit(100000)).value == bytes
  var damaged = bytes
  damaged[0] = damaged[0] xor 1
  assert replaceAtomicFile(PathName, damaged, ByteLimit(100000)) == AtomicFileError.None
  let refused = loadRecoveryCheckpoint(PathName, wire, expected, genesisStoreLimits(), ByteLimit(100000))
  assert refused.fileFailure.error == ApplicationCheckpointFileError.IdentityFailure
  assert readBoundedFile(PathName, ByteLimit(100000)).value ==
      damaged # No implicit recovery rewrites corrupted evidence.
  echo "PASS application recovery files: bounded exact selection, independent trust, typed refusal and no repair"
try:
  main() # Native/fixture failures cannot become successful recovery.
except:
  quit(2)
