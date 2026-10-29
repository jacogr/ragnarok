# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"arc": "application_checkpoint_decode_arc_release"}

## Independent context gates complete-map allocation and every malformed envelope remains payload-free.
import std/[assertions, envvars, syncio]
import ../../../src/app/chain
import ../../../src/app/checkpoint/[codec as checkpoint_codec, identity as checkpoint_identity]
import ../../../src/chain/genesis
import ../../../src/codec/bounded
import ../../../src/codec/state/trie as state_trie
import ../../../src/state/[checkpoint, store]
import ../../support/[application_checkpoint_context, arc_evidence]
proc matches(state, original: StateStoreSnapshot) =
  ## Full root/count and every original key/value exclude omitted or added entries in restored maps.
  assert state.commitment.entries == original.commitment.entries
  assert state.commitment.nodes == original.commitment.nodes
  assert array[32, byte](state.commitment.root) == array[32, byte](original.commitment.root)
  for index in 0..<original.commitment.entries:
    let key = original.keyAt(StateEntryIndex(index)).value
    assert state.lookup(key).value.bytes == original.lookup(
        key).value.bytes # Exact count equality also rules out extra restored keys.
proc cycle(bytes: seq[byte], expected: ApplicationCheckpointIdentity,
    original: StateStoreSnapshot) =
  ## Complete temporary restored graphs retire on this synchronous caller thread.
  let restored = decodeApplicationCheckpoint(bytes, expected, genesisStoreLimits(), ByteLimit(
      uint64(bytes.len))).value
  matches(restored.snapshot.value, original)
proc main() {.raises.} =
  ## Trust comes only from the separately captured application context, never from the envelope being loaded.
  let owner = checkpointFixture()
  let expected = captureApplicationCheckpointIdentity(owner).value
  let original = owner.stateSnapshot.value
  let bytes = encodeApplicationCheckpoint(owner, ByteLimit(high(uint64))).value
  let absent = default(ApplicationCheckpointIdentity)
  assert decodeApplicationCheckpoint(bytes, absent, genesisStoreLimits(), ByteLimit(high(
      uint64))).identityError == ApplicationCheckpointIdentityError.Uninitialized
  for variant in [CheckpointFixtureVariant.Header, CheckpointFixtureVariant.Profile,
      CheckpointFixtureVariant.State]:
    let different = captureApplicationCheckpointIdentity(checkpointFixture(variant)).value
    assert decodeApplicationCheckpoint(bytes, different, default(StateStoreLimits), ByteLimit(high(
        uint64))).error ==
        ApplicationCheckpointError.ContextMismatch # Independent mismatch precedes any restored map/resource processing.
  for extent in 0..<bytes.len:
    assert decodeApplicationCheckpoint(bytes.toOpenArray(0, extent - 1), expected,
        genesisStoreLimits(), ByteLimit(high(uint64))).error != ApplicationCheckpointError.None
  for index in 0..<bytes.len:
    var corrupt = newSeq[byte](bytes.len)
    for offset, octet in bytes:
      corrupt[offset] = octet # No malformed case aliases its original exact source bytes.
    corrupt[index] = corrupt[index] xor 1
    assert decodeApplicationCheckpoint(corrupt, expected, genesisStoreLimits(), ByteLimit(high(
        uint64))).error !=
        ApplicationCheckpointError.None # Identity integrity and full-map root verification cover all octets.
  assert decodeApplicationCheckpoint(bytes, expected, genesisStoreLimits(), ByteLimit(uint64(
      bytes.len - 1))).error == ApplicationCheckpointError.LimitExceeded
  assert decodeApplicationCheckpoint(bytes, expected, default(StateStoreLimits), ByteLimit(high(
      uint64))).error == ApplicationCheckpointError.LimitExceeded
  var extended = bytes
  extended.add(0)
  assert decodeApplicationCheckpoint(extended, expected, genesisStoreLimits(), ByteLimit(high(
      uint64))).checkpointError == CheckpointError.InvalidFormat
  cycle(bytes, expected, original)
  let before = getOccupiedMem()
  for iteration in 0..<1000:
    cycle(bytes, expected, original) # Source policy is explicit; restoration cannot infer writable mutation quotas.
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("application_checkpoint_decode", 1000, before, after)
  var mutableInput = bytes
  let restored = decodeApplicationCheckpoint(mutableInput, expected, genesisStoreLimits(),
      ByteLimit(high(uint64))).value
  mutableInput[mutableInput.high] = mutableInput[mutableInput.high] xor 1
  matches(restored.snapshot.value, original)
  echo "PASS application checkpoint decode: independent context, exact full maps, tamper refusal and owned recovery"
try:
  main() # Fixture/native errors remain nonzero failures, never zero-case recovery evidence.
except:
  quit(2)
