# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Local head context preserves exact state ownership and rejects mismatched chain/profile/header/revision facts.
import std/[assertions, syncio]
import ../../support/application_checkpoint_context
import ../../../src/app/[chain, checkpoint_identity, disk_head]
import ../../../src/chain/[genesis, provider, parameters]
import ../../../src/state/store
import ../../../src/storage/[database_identity, node_repository]
import ../../../src/codec/[bounded, header]
proc main() {.raises.} =
  ## The contextual journal supplies local authority; every application fact still has to match exactly.
  let owner = checkpointFixture()
  let identity = captureApplicationCheckpointIdentity(owner).value
  let state = owner.stateSnapshot.value
  let chain = StorageChainId(array[32, byte](identity.blockHash))
  let generation = RepositoryGeneration(7)
  let limit = ByteLimit(262144)
  let wire = encodeDiskHead(owner, chain, generation, limit).value
  let restored = restoreDiskHead(wire, chain, generation, identity.parameters, state, limit).value
  assert sameApplicationCheckpoint(captureApplicationCheckpointIdentity(restored).value, identity)
  assert sameStateSnapshot(state, restored.stateSnapshot.value)
  assert restored.chainView.finalizedBlock.error == GenesisError.Unavailable
  assert restored.chainView.parentOf(identity.blockHash).error == GenesisError.Unavailable
  assert encodeDiskHead(restored, chain, generation, limit).value == wire
  # Fixed prefix, exact header extent and output ceilings refuse before any partial owner escapes.
  for stop in [0, 1, DiskHeadPrefixBytes-1, DiskHeadPrefixBytes, DiskHeadPrefixBytes+1, wire.high]:
    assert restoreDiskHead(wire.toOpenArray(0, stop-1), chain, generation, identity.parameters,
        state, limit).error != DiskHeadError.None
  assert encodeDiskHead(owner, chain, generation, ByteLimit(wire.len-1)).error ==
      DiskHeadError.LimitExceeded
  assert restoreDiskHead(wire, chain, generation, identity.parameters, state, ByteLimit(
      wire.len-1)).error == DiskHeadError.LimitExceeded
  let absent = default(ApplicationChain)
  assert encodeDiskHead(absent, chain, generation, limit).error ==
      DiskHeadError.IdentityFailure
  assert encodeDiskHead(owner, chain, RepositoryGeneration(0), limit).error ==
      DiskHeadError.GenerationMismatch
  assert restoreDiskHead(wire, chain, RepositoryGeneration(8), identity.parameters, state,
      limit).error == DiskHeadError.GenerationMismatch
  var wrongChain = array[32, byte](chain)
  wrongChain[0] = wrongChain[0] xor 1
  assert restoreDiskHead(wire, StorageChainId(wrongChain), generation, identity.parameters, state,
      limit).error == DiskHeadError.WrongChain
  let absentState = default(StateStoreSnapshot)
  assert restoreDiskHead(wire, chain, generation, identity.parameters, absentState,
      limit).error == DiskHeadError.StateFailure
  let profile = checkpointFixture(CheckpointFixtureVariant.Profile)
  let otherIdentity = captureApplicationCheckpointIdentity(profile).value
  assert restoreDiskHead(wire, chain, generation, otherIdentity.parameters, state, limit).error ==
      DiskHeadError.ContextMismatch
  let changed = checkpointFixture(CheckpointFixtureVariant.State)
  assert restoreDiskHead(wire, chain, generation, identity.parameters, changed.stateSnapshot.value,
      limit).error == DiskHeadError.ContextMismatch
  var modified = wire
  modified[modified.high] = modified[modified.high] xor 1
  assert restoreDiskHead(modified, chain, generation, identity.parameters, state, limit).error ==
      DiskHeadError.ContextMismatch
  modified = wire
  for index in DiskHeadPrefixBytes-8..<DiskHeadPrefixBytes: modified[index] = 255
  assert restoreDiskHead(modified, chain, generation, identity.parameters, state, limit).error ==
      DiskHeadError.InvalidFormat
proc bodyWitness() {.raises.} =
  ## A structural empty extrinsic exercises V2 framing; genuine accepted bytes are checked by disk_chain.
  let owner = checkpointFixture()
  let identity = captureApplicationCheckpointIdentity(owner).value
  let snapshot = owner.chainView.bestBlock.value
  var body = newSeq[byte](snapshot.header.headerInfo.value.consumed+7)
  assert encodeOwnedHeader(snapshot.header, body).error == HeaderError.None
  let captured = withBlockBody(snapshot, body)
  let complete = initApplicationChain(genesisView(captured)).value
  let chain = default(StorageChainId)
  let generation = RepositoryGeneration(7)
  let limit = ByteLimit(262144)
  let encoded = encodeDiskHead(complete, chain, generation, limit).value
  let restored = restoreDiskHead(encoded, chain, generation, identity.parameters,
    owner.stateSnapshot.value, limit).value
  assert restored.chainView.bestBlock.value.blockBody == body
  assert encodeDiskHead(restored, chain, generation, limit).value == encoded
  assert not sameChainView(owner.chainView, complete.chainView) # Body availability is part of exact publication authority.
  for stop in 0..<encoded.len:
    assert restoreDiskHead(encoded.toOpenArray(0, stop-1), chain, generation,
      identity.parameters, owner.stateSnapshot.value, limit).error != DiskHeadError.None
  var modified = encoded
  for index in DiskBodyHeadPrefixBytes-8..<DiskBodyHeadPrefixBytes: modified[index] = 255
  assert restoreDiskHead(modified, chain, generation, identity.parameters,
    owner.stateSnapshot.value, limit).error == DiskHeadError.InvalidFormat
  modified = encoded
  modified[modified.high] = 127 # The last extrinsic sequence is truncated, despite intact header/state identity.
  assert restoreDiskHead(modified, chain, generation, identity.parameters,
    owner.stateSnapshot.value, limit).error == DiskHeadError.CaptureFailure
  var trailing = body
  trailing.add(0'u8)
  assert withBlockBody(snapshot, trailing).error == GenesisError.Invalid
  assert withBlockBody(snapshot, []).error == GenesisError.Invalid
try:
  main()
  bodyWitness()
except:
  quit(2) # Missing or invalid fixture inputs cannot satisfy a context-refusal witness.
echo "PASS disk application head: exact local context, retained snapshot, profile, header and generation checks"
