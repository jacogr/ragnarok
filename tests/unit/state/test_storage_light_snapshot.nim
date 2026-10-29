# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Strict light images use independent chain/root expectations, canonical finite grammar and reverified proof authority.
# @@Verification={"arc": "storage_light_snapshot_arc_release"}
import std/[assertions, syncio]
import ../../support/arc_evidence
import ../../../src/storage/light/[snapshot as light_snapshot, state_cache as light_state_cache]
import ../../../src/storage/state_proof
import ../../../src/storage/full/state_trie as full_state_trie
import ../../../src/storage/database_identity
import ../../../src/codec/bounded
import ../../../src/codec/state/[layout as state_layout, trie as state_trie]
import ../../../src/crypto/primitives
proc reset(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Quota/identity/shape refusal must precede all real checksum and proof hashes.
proc refuseAfter(successful: cint) {.importc: "ro_blake_after", cdecl.}
  ## Exercise every checksum/proof prefix and retire completed private lookup scratch on refusal.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Complete fixed-fixture preparation/restoration requires exactly eight primitive attempts.
const
  Magic = "RAGNAROK-LIGHT-CACHE-V1\n"
  Header = Magic.len+72
proc key(index: int): StateKey =
  ## Every serialized key octet remains fixed and canonical; root polarity is selected by the first.
  var raw = default(array[31, byte])
  raw[0] = byte(index)
  StateKey(raw)
proc limits(): LightSnapshotLimits =
  ## Snapshot restoration is independent of the returned cache's zero mutation allowance.
  LightSnapshotLimits(bytes: ByteLimit(8192), cache: LightCacheLimits(items: ElementLimit(8),
    writes: ElementLimit(0), valueBytes: ByteLimit(256),
    proof: StateProofLimits(nodes: ElementLimit(249), valueBytes: ByteLimit(256))))
proc fixture(): FullStateTrie =
  ## A separate complete-map calculator supplies the trusted root without consulting stored metadata.
  reset(0)
  let entries = [StateEntry(key: key(0), value: newSeq[byte](33)), StateEntry(key: key(128))]
  let policy = StateTrieLimits(items: ElementLimit(8), nodes: TrieNodeLimit(10000),
    perValue: ByteLimit(256), totalValueBytes: ByteLimit(256))
  let expected = stateTrieRoot(entries, policy).value
  let trie = newFullStateTrie(entries, FullStateTrieLimits(trie: policy)).value
  assert array[32, byte](expected.root) == array[32, byte](trie.commitment.root)
  trie
proc proofs(trie: FullStateTrie): seq[LightStateProof] =
  ## Deliberately unsorted transport contains present-empty, present-long and authenticated absence.
  result = @[]
  for number in [255, 128, 0]:
    result.add(LightStateProof(key: key(number), proof: trie.prove(key(number), limits().cache.proof).value))
proc matches(cache: LightStateCache, root: StateRoot) =
  ## A restored partial cache has three known queries, no invented knowledge and the exact original policy.
  assert array[32, byte](cache.root) == array[32, byte](root)
  assert cache.len == 3 and cache.valueBytes == 33
  assert cache.lookup(key(0)).value.bytes == newSeq[byte](33)
  assert cache.lookup(key(128)).value.kind == StateLookupKind.Present
  assert cache.lookup(key(128)).value.bytes.len == 0
  assert cache.lookup(key(255)).value.kind == StateLookupKind.Absent
  assert cache.lookup(key(64)).error == LightCacheError.UnknownKey
  assert uint64(cache.limits.writes) == 0
  assert cache.admit([LightStateProof(key: key(0))]).error == LightCacheError.LimitExceeded
proc put(output: var seq[byte], offset: int, value: uint64, width = 8) =
  ## Test mutations use documented fixed widths, independently of the production parser.
  for index in 0..<width: output[offset+index] = byte((value shr (8*index)) and 255)
proc rechecksum(input: var seq[byte]) =
  ## Deliberate attackers may recompute file integrity; proof/root authority still has to reject false contents.
  reset(0)
  let stop = input.len-32
  let digest = array[32, byte](blake2b256(input.toOpenArray(0, stop-1)).value)
  for index in 0..<32: input[stop+index] = digest[index]
proc golden() =
  ## A two-query empty-root image has a fixed checksum independently computed with Python hashlib Blake2b-256.
  reset(0)
  let input = [LightStateProof(key: key(128)), LightStateProof(key: key(0))]
  let image = prepareLightSnapshot(default(StorageChainId), default(StateRoot), input, limits()).value
  assert image.initialized and not default(PreparedLightSnapshot).initialized
  let encoded = image.bytes
  assert encoded.len == 210 and Header == 96
  var expected = newSeq[byte](178)
  for index, character in Magic: expected[index] = byte(character)
  expected[Magic.len+64] = 2
  expected[Header+41] = 128 # Both proof counts/raw lengths are canonical zero fields.
  for index in 0..<expected.len: assert encoded[index] == expected[index]
  const Checksum = [243'u8, 50, 107, 187, 72, 62, 96, 134, 70, 174, 74, 11, 53, 234, 32, 212,
    243, 194, 37, 157, 127, 215, 104, 117, 175, 245, 133, 55, 159, 74, 115, 148]
  for index in 0..<32: assert encoded[178+index] == Checksum[index]
  let decoded = decodeLightSnapshot(encoded, default(StorageChainId), default(StateRoot), limits()).value
  assert decoded.len == 2 and decoded.valueBytes == 0
  assert decoded.lookup(key(0)).value.kind == StateLookupKind.Absent
proc roundtrip() =
  ## Prepared and decoded caches remain independent of every caller-owned transport and output buffer.
  let trie = fixture()
  var input = proofs(trie)
  reset(0)
  let prepared = prepareLightSnapshot(default(StorageChainId), trie.commitment.root, input, limits()).value
  assert calls() == 8
  assert prepared.cache.len == 3 and prepared.byteLength == prepared.bytes.len
  assert array[32, byte](prepared.chainId) == default(array[32, byte])
  assert array[32, byte](prepared.root) == array[32, byte](trie.commitment.root)
  input[2].proof.value[0] = 99
  matches(prepared.cache, trie.commitment.root)
  var encoded = prepared.bytes
  reset(0)
  let restored = decodeLightSnapshot(encoded, default(StorageChainId), trie.commitment.root, limits()).value
  assert calls() == 8
  matches(restored, trie.commitment.root)
  encoded[Header+41+2*64] = 88
  matches(prepared.cache, trie.commitment.root)
  matches(restored, trie.commitment.root)
  assert prepared.bytes[Header+41+2*64] == 0
  var copiedPolicy = prepared.limits
  copiedPolicy.cache.writes = ElementLimit(8)
  assert uint64(prepared.cache.limits.writes) == 0
proc malformed() =
  ## Every proper prefix and extra suffix refuses before it can expose a cache or partial proof set.
  let trie = fixture()
  let input = proofs(trie)
  let prepared = prepareLightSnapshot(default(StorageChainId), trie.commitment.root, input, limits()).value
  let bytes = prepared.bytes
  for length in 0..<bytes.len:
    var prefix = newSeq[byte](length)
    for index in 0..<length: prefix[index] = bytes[index]
    let checkedSnapshot1 = decodeLightSnapshot(prefix, default(StorageChainId),
        trie.commitment.root, limits())
    assert checkedSnapshot1.error != LightSnapshotError.None
  var changed = bytes
  changed.add(0)
  let checkedSnapshot2 = decodeLightSnapshot(changed, default(StorageChainId), trie.commitment.root,
      limits())
  assert checkedSnapshot2.error == LightSnapshotError.InvalidFormat
  changed = bytes
  changed[changed.len-1] = changed[changed.len-1] xor 1
  let checkedSnapshot3 = decodeLightSnapshot(changed, default(StorageChainId), trie.commitment.root,
      limits())
  assert checkedSnapshot3.error == LightSnapshotError.ChecksumMismatch
  changed = bytes
  changed[Header+41+2*64] = 1
  rechecksum(changed)
  let falseValue = decodeLightSnapshot(changed, default(StorageChainId), trie.commitment.root,
      limits())
  assert falseValue.error == LightSnapshotError.ProofFailure and falseValue.proofError ==
      LightCacheError.ValueMismatch
  changed = bytes
  # First key is zero; replacing the second key by zero breaks canonical unique ordering before hashing.
  let second = Header+41+2*64+33
  for index in 0..<31: changed[second+index] = 0
  reset(1)
  let checkedSnapshot4 = decodeLightSnapshot(changed, default(StorageChainId), trie.commitment.root,
      limits())
  assert checkedSnapshot4.error == LightSnapshotError.InvalidFormat
  assert calls() == 0
  changed = bytes
  put(changed, Magic.len+64, high(uint64))
  var generous = limits()
  generous.cache.items = ElementLimit(high(uint64))
  let checkedSnapshot5 = decodeLightSnapshot(changed, default(StorageChainId), trie.commitment.root, generous)
  assert checkedSnapshot5.error == LightSnapshotError.LengthOverflow
  assert calls() == 0
  changed = bytes
  put(changed, Header+33, high(uint64))
  generous.cache.proof.valueBytes = ByteLimit(high(uint64))
  generous.cache.valueBytes = ByteLimit(high(uint64))
  let checkedSnapshot6 = decodeLightSnapshot(changed, default(StorageChainId), trie.commitment.root, generous)
  assert checkedSnapshot6.error == LightSnapshotError.InvalidFormat
  assert calls() == 0
  changed = bytes
  put(changed, Header+31, 250, 2)
  generous.cache.proof.nodes = ElementLimit(high(uint64))
  let checkedSnapshot7 = decodeLightSnapshot(changed, default(StorageChainId), trie.commitment.root, generous)
  assert checkedSnapshot7.error == LightSnapshotError.LimitExceeded
  assert calls() == 0
proc boundaries() =
  ## Count/shape/output budgets and independent identity mismatch all refuse before checksum/proof work.
  let trie = fixture()
  let input = proofs(trie)
  let prepared = prepareLightSnapshot(default(StorageChainId), trie.commitment.root, input, limits()).value
  var policy = limits()
  policy.bytes = ByteLimit(prepared.byteLength-1)
  reset(1)
  let checkedSnapshot8 = prepareLightSnapshot(default(StorageChainId), trie.commitment.root, input, policy)
  assert checkedSnapshot8.error == LightSnapshotError.LimitExceeded
  let checkedSnapshot9 = decodeLightSnapshot(prepared.bytes, default(StorageChainId),
      trie.commitment.root, policy)
  assert checkedSnapshot9.error == LightSnapshotError.LimitExceeded
  assert calls() == 0
  policy.bytes = ByteLimit(prepared.byteLength)
  reset(0)
  let exact = prepareLightSnapshot(default(StorageChainId), trie.commitment.root, input, policy).value
  assert exact.byteLength == prepared.byteLength
  for which in 0..<4:
    var tight = limits()
    case which
    of 0: tight.cache.items = ElementLimit(2)
    of 1: tight.cache.proof.nodes = ElementLimit(1)
    of 2: tight.cache.proof.valueBytes = ByteLimit(32)
    else: tight.cache.valueBytes = ByteLimit(32)
    reset(1)
    let checkedSnapshot10 = prepareLightSnapshot(default(StorageChainId), trie.commitment.root,
        input, tight)
    assert checkedSnapshot10.error == LightSnapshotError.LimitExceeded
    let checkedSnapshot11 = decodeLightSnapshot(prepared.bytes, default(StorageChainId),
        trie.commitment.root, tight)
    assert checkedSnapshot11.error == LightSnapshotError.LimitExceeded
    assert calls() == 0
  var different = default(array[32, byte])
  different[0] = 1
  reset(1)
  let checkedSnapshot12 = decodeLightSnapshot(prepared.bytes, StorageChainId(different),
      trie.commitment.root, limits())
  assert checkedSnapshot12.error == LightSnapshotError.WrongChain
  let checkedSnapshot13 = decodeLightSnapshot(prepared.bytes, default(StorageChainId), StateRoot(
      different), limits())
  assert checkedSnapshot13.error == LightSnapshotError.WrongRoot
  assert calls() == 0
  let duplicate = prepareLightSnapshot(default(StorageChainId), trie.commitment.root, [input[0],
      input[0]], limits())
  assert duplicate.error == LightSnapshotError.ProofFailure and duplicate.proofError ==
      LightCacheError.DuplicateKey
  assert calls() == 0
  reset(0)
  let full = encodeDatabaseIdentity(fullStateIdentity(default(StorageChainId)), ByteLimit(1024)).value
  let checkedSnapshot14 = decodeLightSnapshot(full, default(StorageChainId), trie.commitment.root,
      limits())
  assert checkedSnapshot14.error == LightSnapshotError.InvalidFormat
  assert decodeDatabaseIdentity(prepared.bytes, default(StorageChainId), ByteLimit(8192)).error ==
      IdentityError.InvalidFormat
proc refusalPrefixes() =
  ## Each of the eight actual primitive attempts is refused once in both preparation and restoration.
  let trie = fixture()
  let input = proofs(trie)
  let encoded = prepareLightSnapshot(default(StorageChainId), trie.commitment.root, input, limits()).value.bytes
  for successful in 0..<8:
    refuseAfter(cint(successful))
    let checkedSnapshot15 = prepareLightSnapshot(default(StorageChainId), trie.commitment.root,
        input, limits())
    assert checkedSnapshot15.error == LightSnapshotError.BackendFailure
    assert calls() == cint(successful+1)
    refuseAfter(cint(successful))
    let checkedSnapshot16 = decodeLightSnapshot(encoded, default(StorageChainId),
        trie.commitment.root, limits())
    assert checkedSnapshot16.error == LightSnapshotError.BackendFailure
    assert calls() == cint(successful+1)
proc lifecycle() =
  ## Successful images/caches and refusal after completed private lookup scratch retire within each isolated call.
  let trie = fixture()
  let input = proofs(trie)
  refuseAfter(4)
  let checkedSnapshot17 = prepareLightSnapshot(default(StorageChainId), trie.commitment.root, input,
      limits())
  assert checkedSnapshot17.error == LightSnapshotError.BackendFailure
  reset(0)
  let image = prepareLightSnapshot(default(StorageChainId), trie.commitment.root, input, limits()).value
  refuseAfter(5)
  let checkedSnapshot18 = decodeLightSnapshot(image.bytes, default(StorageChainId),
      trie.commitment.root, limits())
  assert checkedSnapshot18.error == LightSnapshotError.BackendFailure
  reset(0)
  let restored = decodeLightSnapshot(image.bytes, default(StorageChainId), trie.commitment.root,
      limits()).value
  matches(restored, trie.commitment.root)
golden()
roundtrip()
malformed()
boundaries()
refusalPrefixes()
reset(0)
let empty = prepareLightSnapshot(default(StorageChainId), default(StateRoot), [], limits()).value
assert empty.cache.len == 0
assert decodeLightSnapshot(empty.bytes, default(StorageChainId), default(StateRoot), limits()).value.len == 0
lifecycle()
let before = getOccupiedMem()
for cycle in 0..<1000: lifecycle()
let after = getOccupiedMem()
assert before == after
recordArcRelease("storage_light_snapshot", 1000, before, after)
echo "PASS storage light snapshots: canonical identity, trusted roots, strict shape, proof revalidation and ownership"
