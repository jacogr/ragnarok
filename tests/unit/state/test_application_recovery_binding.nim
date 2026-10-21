# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"arc": "application_recovery_binding_arc_release"}

## Exact trusted recovery retains one head and immutable policy without fabricating ancestors or finality.
import std/[assertions, syncio]
import ../../../src/app/[chain, checkpoint_identity, checkpoint_recovery]
import ../../../src/chain/[genesis, provider, parameters]
import ../../../src/codec/[header, bounded, state_layout, state_trie]
import ../../../src/state/[store, checkpoint]
import ../../../src/crypto/primitives
import ../../support/[application_checkpoint_context, arc_evidence]
proc headerBytes(owner: ApplicationChain): seq[byte] =
  ## Copy canonical sealed bytes so input mutation cannot modify the recovered owner.
  let header = owner.chainView.bestBlock.value.header
  result = newSeq[byte](header.headerInfo.value.consumed)
  assert encodeOwnedHeader(header, result).error == HeaderError.None
proc cycle(state: StateStoreSnapshot, wire: seq[byte], expected: ApplicationCheckpointIdentity) =
  ## Temporary application forks release all retained aliases on return.
  let recovered = recoverApplicationChain(state, wire, expected).value
  assert sameStateSnapshot(recovered.stateSnapshot.value, state)
  assert recovered.chainView.retainedCount == 1
  assert recovered.chainView.finalizedBlock.error != GenesisError.None
proc main() {.raises.} =
  ## Trust is captured independently of supplied bytes and defaults cannot authorize recovery.
  let original = checkpointFixture()
  let expected = captureApplicationCheckpointIdentity(original).value
  let state = original.stateSnapshot.value
  let wire = headerBytes(original)
  let absent = default(ApplicationCheckpointIdentity)
  assert recoverApplicationChain(state, wire, absent).error == ApplicationRecoveryError.MissingTrust
  let missing = recoverApplicationChain(default(StateStoreSnapshot), wire, expected)
  assert missing.error == ApplicationRecoveryError.StateFailure
  assert missing.stateError == StateStoreError.Uninitialized
  for extent in 0..<wire.len:
    let refused = recoverApplicationChain(state, wire.toOpenArray(0, extent - 1), expected)
    assert refused.error == ApplicationRecoveryError.HeaderFailure # Exact header consumption rejects every cut.
  var extended = wire
  extended.add(0)
  assert recoverApplicationChain(state, extended, expected).error ==
      ApplicationRecoveryError.HeaderFailure
  let other = checkpointFixture(CheckpointFixtureVariant.Header)
  assert recoverApplicationChain(state, headerBytes(other), expected).error ==
      ApplicationRecoveryError.HeaderMismatch
  let changed = checkpointFixture(CheckpointFixtureVariant.State).stateSnapshot.value
  assert recoverApplicationChain(changed, wire, expected).error ==
      ApplicationRecoveryError.ContextMismatch
  var changedTrust = encodeApplicationCheckpointIdentity(expected, ByteLimit(238)).value
  changedTrust[80] = changedTrust[80] xor 1
  let checksum = blake2b256(changedTrust.toOpenArray(0, 205)).value
  for index in 0..<32:
    changedTrust[206 + index] = array[32, byte](checksum)[
        index] # Independent valid metadata asks for a different time.
  let wrongTime = decodeApplicationCheckpointIdentity(changedTrust, ByteLimit(238)).value
  assert recoverApplicationChain(state, wire, wrongTime).error ==
      ApplicationRecoveryError.ContextMismatch
  var mutableWire = wire
  let recovered = recoverApplicationChain(state, mutableWire, expected).value
  mutableWire[mutableWire.high] = mutableWire[mutableWire.high] xor 1
  assert sameApplicationCheckpoint(captureApplicationCheckpointIdentity(recovered).value, expected)
  assert recovered.chainView.parentOf(expected.blockHash).error != GenesisError.None
  assert recovered.chainView.bestBlock.value.chainParameters.encodeParameters ==
      expected.parameters.encodeParameters
  var limits = genesisStoreLimits()
  limits.writes = ElementLimit(1)
  limits.writeValueBytes = ByteLimit(1)
  let bytes = encodeFullCheckpoint(state, ByteLimit(high(uint64))).value
  let restored = decodeFullCheckpoint(bytes, expected.stateRoot, limits, ByteLimit(high(uint64))).value
  let writable = recoverApplicationChain(restored.snapshot.value, wire, expected).value
  var branch = forkStateStore(writable.stateSnapshot.value).value
  let updated = branch.apply([StateWrite(key: chapterKey(StateChapter(250)),
      kind: StateWriteKind.Put, value: @[1'u8])])
  assert updated.error == StateStoreError.None
  assert writable.stateSnapshot.value.lookup(chapterKey(StateChapter(250))).error ==
      StateStoreError.MissingKey
  cycle(state, wire, expected)
  let before = getOccupiedMem()
  for iteration in 0..<1000:
    cycle(state, wire, expected) # Retained snapshot/header ownership must not accumulate.
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("application_recovery_binding", 1000, before, after)
  echo "PASS application recovery binding: trusted exact head, immutable map, one retained block and unset finality"
try:
  main() # Fixture/native errors cannot pass as empty test coverage.
except:
  quit(2)
