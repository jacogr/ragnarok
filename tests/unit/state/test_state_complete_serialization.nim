# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Independently authored complete bytes qualify typed composition and explicit-root checkpoint restoration.
import std/[assertions, envvars, strutils, syncio, parseutils]
import ../../../src/crypto/primitives
import ../../../src/state/[checkpoint, store, manifest, global_snapshot, validated_checkpoint]
import ../../../src/codec/[bounded, assurances, state_consensus, state_layout, state_trie,
  state_composition, state_accounts, state_service_values, state_requests]
include ../../native/composition_fixture
const
  sizes = [0, 1, 31, 32, 33, 63, 64, 65]
  profile = StateProfile(cores: CoreCount(2), current: ValidatorCount(6),
    previous: ValidatorCount(6), epochSlots: EpochSlots(2))
  mapLimits = StateTrieLimits(items: ElementLimit(20), nodes: TrieNodeLimit(2048),
    perValue: ByteLimit(65536), totalValueBytes: ByteLimit(262144))
  stores = StateStoreLimits(trie: mapLimits, writes: ElementLimit(20), writeValueBytes: ByteLimit(262144))
  limits = StateCheckpointLimits(checkpointBytes: ByteLimit(524288), store: stores,
    globals: GlobalStateLimits(chapter: StateChapterPolicy(items: ElementLimit(1000),
      maxBytes: ByteLimit(65536)), totalBytes: ByteLimit(262144)),
    manifest: StateManifestLimits(services: ElementLimit(1), serialized: mapLimits,
      storageKeyBytes: ByteLimit(65)))
proc word(caseId, field, bits: int): uint64 =
  ## Fingerprint logical inputs without encoding them; zero/all-ones exercise unsigned domains.
  if caseId mod 8 == 0: return 0
  if caseId mod 8 == 1:
    if bits == 32: return uint64(high(uint32))
    return high(uint64)
  (uint64(caseId) shl (bits-8)) or (uint64(field) shl (bits-16)) or 0x0102'u64
proc octets(text: string): seq[byte] =
  ## Decode only the pinned fixture's complete hex octets; malformed setup cannot qualify a case.
  assert text.len mod 2 == 0
  result = newSeq[byte](text.len div 2)
  for i in 0..<result.len:
    var octet: byte = 0
    assert parseHex(text[2*i..2*i+1], octet) == 2
    result[i] = octet
proc pattern(size, seed: int): seq[byte] =
  ## Author raw storage and preimage inputs across inline/hash and block-size boundaries.
  result = newSeq[byte](size)
  for i in 0..<size: result[i] = byte((seed+i) mod 256)
proc check(fixture: seq[seq[byte]], expected: seq[byte], caseId: int) =
  ## Compose logical fields and require every envelope byte before decoding independently supplied bytes.
  var chapters = default(StateChapters)
  for i in 1..16:
    var input = fixture[i-1]
    if i == 11:
      input = newSeq[byte](4)
      for j in 0..<4: input[j] = byte((word(caseId, 1, 32) shr (j*8)) and 255)
    chapters[StateChapterId(i)] = captureStateChapter(StateChapterId(i), input, profile,
      limits.globals.chapter).value
  let rawKey = pattern(sizes[caseId mod 8], caseId)
  let stored = pattern(sizes[(caseId+2) mod 8], 3*caseId)
  let payload = pattern(sizes[(caseId+4) mod 8], 7*caseId)
  # Hash only the logical input payload; complete expected keys and roots come from Python.
  var identity = default(array[32, byte])
  let contentHash = blake2b256(payload)
  assert contentHash.error == CryptoError.None
  identity = array[32, byte](contentHash.value)
  var code = default(array[32, byte])
  for i in 0..<32: code[i] = byte(i)
  let metadata = ServiceMetadata(codeHash: CodeHash(code),
    balance: AccountBalance(word(caseId, 1, 64)), supervisorBalance: AccountBalance(word(caseId, 2, 64)),
    minimumAccumulationGas: Gas(word(caseId, 3, 64)), minimumTransferGas: Gas(word(caseId, 4, 64)),
    storageBytes: AccountStorageBytes(uint64(115+rawKey.len+stored.len+payload.len)),
    depositOffset: AccountBalance(word(caseId, 6, 64)), storageItems: AccountStorageItems(3),
    created: AccountSlot(uint32(word(caseId, 2, 32))), lastAccumulation: AccountSlot(uint32(word(
        caseId, 3, 32))),
    parent: ServiceIndex(uint32(word(caseId, 4, 32))), supervisor: ServiceIndex(uint32(word(caseId,
        5, 32))),
    supervisorCreated: AccountSlot(uint32(word(caseId, 6, 32))))
  let id = [0'u32, high(uint32), 0x01020304'u32, 256'u32][caseId mod 4]
  var history = requestedHistory()
  case caseId mod 4
  of 1: history = availableHistory(RequestSlot(1))
  of 2: history = unavailableHistory(RequestSlot(1), RequestSlot(2))
  of 3: history = reavailableHistory(RequestSlot(1), RequestSlot(2), RequestSlot(3))
  else: discard # The empty requested mode remains a real serialized key/value entry.
  let services = @[StateService(service: ServiceIndex(id), metadata: metadata,
    storage: @[StateStorageItem(key: rawKey, value: stored)],
    preimages: @[StatePreimageItem(hash: ServicePreimageHash(identity), value: payload)],
    requests: @[StateRequestItem(hash: ServicePreimageHash(identity), length: RequestLength(uint32(
        payload.len)), history: history)])]
  let composed = composeState(chapters, services, mapLimits, ByteLimit(65)).value
  var entries: seq[StateEntry] = @[]
  for i in 0..<20: entries.add(composed.stateEntryAt(state_composition.StateEntryIndex(uint64(i))).value)
  let snapshot = newStateStore(entries, stores).value.snapshot.value
  assert encodeFullCheckpoint(snapshot, limits.checkpointBytes).value == expected
  # The expected root is copied from Python-authored bytes, independently of the native composition.
  var root = default(array[32, byte])
  for i in 0..<32: root[i] = expected[25+i]
  let restored = decodeValidatedCheckpoint(expected, StateRoot(root), services, profile, limits)
  assert restored.error == ValidatedCheckpointError.None
  assert encodeFullCheckpoint(restored.value.manifestSource.value, limits.checkpointBytes).value == expected
proc main() {.raises.} =
  ## Run every pinned independent complete state; require exact fixture cardinality and no skipped rows.
  let fixture = compositionFixture(getEnv("RAGNAROK_COMPOSITION_FIXTURE"))
  let lines = readFile(getEnv("RAGNAROK_COMPLETE_SERIALIZATION")).splitLines()
  var count = 0
  for line in lines:
    if line.len == 0: continue # Only the final newline is ignorable fixture framing.
    assert count < 32
    check(fixture, octets(line), count)
    inc count
  assert count == 32
  echo "state-complete-serialization: ok (32 cases)"
try:
  main()
except:
  quit(2) # Missing or malformed fixtures cannot count as successful serialization checks.
