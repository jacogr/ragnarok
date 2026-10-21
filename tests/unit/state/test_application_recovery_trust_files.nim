# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"arc": "application_recovery_trust_files_arc_release"}

## Separate operator trust files are bounded and captured once before any checkpoint recovery.
import std/[assertions, syncio]
import std/posix/posix
import ../../../src/app/[chain, checkpoint_identity, checkpoint_codec, checkpoint_recovery, checkpoint_trust]
import ../../../src/chain/[genesis, provider]
import ../../../src/codec/[bounded, header]
import ../../../src/lib/atomic_file
import ../../support/[application_checkpoint_context, arc_evidence]
const IdentityPath = "application-recovery-operator-identity"
const HeaderPath = "application-recovery-operator-header"
proc cycle(envelope: seq[byte], expected: ApplicationCheckpointIdentity) =
  ## File descriptors, captured header and complete recovered graph all retire on this host.
  let trust = loadCheckpointTrust(IdentityPath, HeaderPath, ByteLimit(300000)).value
  let owner = decodeTrustedCheckpoint(envelope, trust, genesisStoreLimits(), ByteLimit(high(uint64))).value
  assert sameApplicationCheckpoint(captureApplicationCheckpointIdentity(owner).value, expected)
proc main() {.raises.} =
  ## Bounded regular-file reads never infer trust from checkpoint metadata or repair failed input.
  var identityPath = IdentityPath
  var headerPath = HeaderPath
  defer: discard posix.unlink(identityPath.toCString())
  defer: discard posix.unlink(headerPath.toCString())
  let source = checkpointFixture()
  let expected = captureApplicationCheckpointIdentity(source).value
  let metadata = encodeApplicationCheckpointIdentity(expected, ByteLimit(238)).value
  let envelope = encodeApplicationCheckpoint(source, ByteLimit(high(uint64))).value
  let header = source.chainView.bestBlock.value.header
  var wire = newSeq[byte](header.headerInfo.value.consumed)
  assert encodeOwnedHeader(header, wire).error == HeaderError.None
  assert replaceAtomicFile(IdentityPath, metadata, ByteLimit(238)) == AtomicFileError.None
  assert replaceAtomicFile(HeaderPath, wire, ByteLimit(300000)) == AtomicFileError.None
  let extent = uint64(metadata.len + wire.len)
  assert loadCheckpointTrust(IdentityPath, HeaderPath, ByteLimit(extent)).error ==
      CheckpointTrustError.None
  assert loadCheckpointTrust(IdentityPath, HeaderPath, ByteLimit(237)).error ==
      CheckpointTrustError.LimitExceeded
  assert loadCheckpointTrust(IdentityPath, HeaderPath, ByteLimit(extent - 1)).fileError ==
      AtomicFileError.LimitExceeded
  assert loadCheckpointTrust("", HeaderPath, ByteLimit(extent)).fileError ==
      AtomicFileError.InvalidPath
  assert loadCheckpointTrust(IdentityPath, "missing", ByteLimit(extent)).fileError ==
      AtomicFileError.IoFailure
  cycle(envelope, expected)
  let before = getOccupiedMem()
  for iteration in 0..<1000:
    cycle(envelope, expected) # Complete startup attempts cannot retain descriptors or decoded graphs.
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("application_recovery_trust_files", 1000, before, after)
  let retained = loadCheckpointTrust(IdentityPath, HeaderPath, ByteLimit(extent)).value
  var changed = wire
  changed[changed.high] = changed[changed.high] xor 1
  assert replaceAtomicFile(HeaderPath, changed, ByteLimit(300000)) == AtomicFileError.None
  assert loadCheckpointTrust(IdentityPath, HeaderPath, ByteLimit(extent)).error ==
      CheckpointTrustError.HeaderMismatch
  assert decodeTrustedCheckpoint(envelope, retained, genesisStoreLimits(), ByteLimit(high(
      uint64))).error == ApplicationRecoveryError.None
  assert readBoundedFile(HeaderPath, ByteLimit(300000)).value ==
      changed # Refusal neither repairs nor silently rereads the captured owner's inputs.
  var oversizedIdentity = metadata
  oversizedIdentity.add(0)
  assert replaceAtomicFile(IdentityPath, oversizedIdentity, ByteLimit(239)) == AtomicFileError.None
  assert loadCheckpointTrust(IdentityPath, HeaderPath, ByteLimit(300000)).fileError ==
      AtomicFileError.LimitExceeded
  assert replaceAtomicFile(IdentityPath, [], ByteLimit(0)) == AtomicFileError.None
  let invalid = loadCheckpointTrust(IdentityPath, "missing", ByteLimit(300000))
  assert invalid.error == CheckpointTrustError.IdentityFailure # Identity validation precedes header open errors.
  echo "PASS application recovery trust files: bounded independent paths, exact capture, no reread and typed refusal"
try:
  main() # Native/fixture errors are never partial recovery success.
except:
  quit(2)
