# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"arc": "application_recovery_envelope_arc_release"}

## Complete envelope restoration and trusted header binding remain one all-or-nothing canonical construction.
import std/assertions
import std/syncio
import ../../../src/app/chain as app_chain
import ../../../src/app/checkpoint_identity as app_checkpoint_identity
import ../../../src/app/checkpoint_codec as app_checkpoint_codec
import ../../../src/app/checkpoint_recovery as app_checkpoint_recovery
import ../../../src/chain/genesis as chain_genesis
import ../../../src/chain/provider as chain_provider
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/header as codec_header
import ../../../src/state/store as state_store
import ../../support/app_checkpoint_context
import ../../support/testing_arc_evidence
proc cycle(bytes, wire: seq[byte], expected: ApplicationCheckpointIdentity,
    original: StateStoreSnapshot) =
  ## Complete restored map/header owners retire on the allocating host thread.
  let owner = decodeRecoveryCheckpoint(bytes, wire, expected, genesisStoreLimits(), ByteLimit(high(uint64))).value
  assert sameApplicationCheckpoint(captureApplicationCheckpointIdentity(owner).value, expected)
  assert owner.chainView.retainedCount == 1
  assert owner.chainView.finalizedBlock.error != GenesisError.None
  let state = owner.stateSnapshot.value
  assert state.commitment.entries == original.commitment.entries
  for index in 0..<original.commitment.entries:
    let key = original.keyAt(StateEntryIndex(index)).value
    assert state.lookup(key).value.bytes == original.lookup(
        key).value.bytes # Count plus exact original entries rules out additions and omissions.
proc main() {.raises.} =
  ## Restore only from independent trust and exact caller-selected map/byte limits.
  let source = checkpointFixture()
  let expected = captureApplicationCheckpointIdentity(source).value
  let bytes = encodeApplicationCheckpoint(source, ByteLimit(high(uint64))).value
  let header = source.chainView.bestBlock.value.header
  var wire = newSeq[byte](header.headerInfo.value.consumed)
  assert encodeOwnedHeader(header, wire).error == HeaderError.None
  let absent = default(ApplicationCheckpointIdentity)
  assert decodeRecoveryCheckpoint([], [], absent, default(StateStoreLimits), ByteLimit(0)).error ==
      ApplicationRecoveryError.MissingTrust
  for variant in [CheckpointFixtureVariant.Header, CheckpointFixtureVariant.Profile,
      CheckpointFixtureVariant.State]:
    let other = captureApplicationCheckpointIdentity(checkpointFixture(variant)).value
    let refused = decodeRecoveryCheckpoint(bytes, wire, other, default(StateStoreLimits), ByteLimit(
        high(uint64)))
    assert refused.error == ApplicationRecoveryError.EnvelopeFailure
    assert refused.envelopeFailure.error == ApplicationCheckpointError.ContextMismatch
  for extent in 0..<bytes.len:
    let refused = decodeRecoveryCheckpoint(bytes.toOpenArray(0, extent - 1), wire, expected,
        genesisStoreLimits(), ByteLimit(high(uint64)))
    assert refused.error == ApplicationRecoveryError.EnvelopeFailure # Every cut refuses before any canonical owner escapes.
  let tightBytes = decodeRecoveryCheckpoint(bytes, wire, expected, genesisStoreLimits(), ByteLimit(
      uint64(bytes.len - 1)))
  assert tightBytes.envelopeFailure.error == ApplicationCheckpointError.LimitExceeded
  let tightMap = decodeRecoveryCheckpoint(bytes, wire, expected, default(StateStoreLimits),
      ByteLimit(high(uint64)))
  assert tightMap.envelopeFailure.error == ApplicationCheckpointError.LimitExceeded
  var wrongHeader = wire
  wrongHeader[wrongHeader.high] = wrongHeader[wrongHeader.high] xor 1
  assert decodeRecoveryCheckpoint(bytes, wrongHeader, expected, genesisStoreLimits(), ByteLimit(
      high(uint64))).error == ApplicationRecoveryError.HeaderMismatch
  cycle(bytes, wire, expected, source.stateSnapshot.value)
  let before = getOccupiedMem()
  for iteration in 0..<1000:
    cycle(bytes, wire, expected, source.stateSnapshot.value) # Complete temporary graphs must release between recoveries.
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("app_recovery_envelope", 1000, before, after)
  var mutableBytes = bytes
  let detached = decodeRecoveryCheckpoint(mutableBytes, wire, expected, genesisStoreLimits(),
      ByteLimit(high(uint64))).value
  mutableBytes[mutableBytes.high] = mutableBytes[mutableBytes.high] xor 1
  assert sameApplicationCheckpoint(captureApplicationCheckpointIdentity(detached).value, expected)
  echo "PASS application recovery envelope: independent trust, exact complete map, explicit ceilings and detached canonical ownership"
try:
  main() # Fixture/native failures cannot become successful partial recovery.
except:
  quit(2)
