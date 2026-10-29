# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"arc": "application_recovery_trust_arc_release"}

## Operator-selected metadata/header bytes are bounded, hash-bound and detached before checkpoint access.
import std/[assertions, syncio]
import ../../../src/app/chain
import ../../../src/app/checkpoint/[identity as checkpoint_identity, codec as checkpoint_codec,
    recovery as checkpoint_recovery, trust as checkpoint_trust]
import ../../../src/chain/[genesis, provider]
import ../../../src/codec/[bounded, header]
import ../../../src/state/store
import ../../support/[application_checkpoint_context, arc_evidence]
proc cycle(metadata, wire, envelope: seq[byte], expected: ApplicationCheckpointIdentity) =
  ## Captured sealed bytes and complete restored graph release on the host at return.
  let trust = captureCheckpointTrust(metadata, wire, ByteLimit(high(uint64))).value
  let owner = decodeTrustedCheckpoint(envelope, trust, genesisStoreLimits(), ByteLimit(high(uint64))).value
  assert sameApplicationCheckpoint(captureApplicationCheckpointIdentity(owner).value, expected)
proc main() {.raises.} =
  ## Independent fixed identity is an operator input; envelope contents never provide trust automatically.
  let source = checkpointFixture()
  let expected = captureApplicationCheckpointIdentity(source).value
  let metadata = encodeApplicationCheckpointIdentity(expected, ByteLimit(238)).value
  let envelope = encodeApplicationCheckpoint(source, ByteLimit(high(uint64))).value
  let header = source.chainView.bestBlock.value.header
  var wire = newSeq[byte](header.headerInfo.value.consumed)
  assert encodeOwnedHeader(header, wire).error == HeaderError.None
  let absent = default(TrustedApplicationCheckpoint)
  assert not absent.ready
  assert decodeTrustedCheckpoint(envelope, absent, genesisStoreLimits(), ByteLimit(high(
      uint64))).error == ApplicationRecoveryError.MissingTrust
  assert loadTrustedCheckpoint("missing", absent, genesisStoreLimits(), ByteLimit(0)).error ==
      ApplicationRecoveryError.MissingTrust
  let extent = uint64(metadata.len + wire.len)
  assert captureCheckpointTrust(metadata, wire, ByteLimit(extent - 1)).error ==
      CheckpointTrustError.LimitExceeded
  assert captureCheckpointTrust(metadata, wire, ByteLimit(extent)).error ==
      CheckpointTrustError.None
  assert captureCheckpointTrust([], wire, ByteLimit(high(uint64))).error ==
      CheckpointTrustError.IdentityFailure
  assert captureCheckpointTrust(metadata, [], ByteLimit(high(uint64))).error ==
      CheckpointTrustError.InvalidHeader
  let oversized = newSeq[byte](MaxRecoveryHeaderBytes + 1)
  assert captureCheckpointTrust(metadata, oversized, ByteLimit(high(uint64))).error ==
      CheckpointTrustError.InvalidHeader
  for length in 1..<wire.len:
    let refused = captureCheckpointTrust(metadata, wire.toOpenArray(0, length - 1), ByteLimit(high(uint64)))
    assert refused.error == CheckpointTrustError.HeaderMismatch # Exact full sealed bytes are mandatory even before map decoding.
  var damaged = metadata
  damaged[damaged.high] = damaged[damaged.high] xor 1
  assert captureCheckpointTrust(damaged, wire, ByteLimit(high(uint64))).identityError ==
      ApplicationCheckpointIdentityError.ChecksumMismatch
  var mutableMetadata = metadata
  var mutableWire = wire
  let trust = captureCheckpointTrust(mutableMetadata, mutableWire, ByteLimit(extent)).value
  mutableMetadata[0] = 0
  mutableWire[mutableWire.high] = mutableWire[mutableWire.high] xor 1
  assert trust.ready and sameApplicationCheckpoint(trust.identity, expected)
  assert decodeTrustedCheckpoint(envelope, trust, genesisStoreLimits(), ByteLimit(high(
      uint64))).error == ApplicationRecoveryError.None
  cycle(metadata, wire, envelope, expected)
  let before = getOccupiedMem()
  for iteration in 0..<1000:
    cycle(metadata, wire, envelope, expected) # Private trust/header and map ownership cannot accumulate.
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("application_recovery_trust", 1000, before, after)
  echo "PASS application recovery trust: bounded independent inputs, exact sealed hash and private detached ownership"
try:
  main() # Fixture/native failures remain real failures.
except:
  quit(2)
