# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Independent root authority and a flat known-key model witness bounded atomic immutable light lookup retention.
# @@Verification={"arc": "storage_light_cache_arc_release"}
import std/[assertions, syncio]
import ../../support/arc_evidence
import ../../../src/storage/light/state_cache as light_state_cache
import ../../../src/storage/state_proof
import ../../../src/storage/full/state_trie as full_state_trie
import ../../../src/codec/state/[layout as state_layout, trie as state_trie]
import ../../../src/codec/bounded
proc reset(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Actual provider refusal must preserve every retained cache and never create absence.
proc refuseAfter(successful: cint) {.importc: "ro_blake_after", cdecl.}
  ## Fail after a complete first proof to exercise retirement of private validated lookup scratch.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Quota/duplicate preflight and forgetting must make zero primitive calls.
const Queries = [0, 64, 128, 192, 250, 251, 252, 253]
proc key(number: int): StateKey =
  ## Full fixed identities spread the known/unknown model across both root directions.
  var raw = default(array[31, byte])
  raw[0] = byte(number)
  StateKey(raw)
proc bytes(index: int): seq[byte] =
  ## Independent model values include present-empty, inline and long payloads.
  let size = [33, 0, 1, 256][index]
  result = newSeq[byte](size)
  for offset in 0..<size: result[offset] = byte((index+offset) and 255)
proc policy(): LightCacheLimits =
  ## Retained values, positive/negative entries and input proof work have distinct ceilings.
  LightCacheLimits(items: ElementLimit(8), writes: ElementLimit(8), valueBytes: ByteLimit(512),
    proof: StateProofLimits(nodes: ElementLimit(249), valueBytes: ByteLimit(256)))
proc fixture(): FullStateTrie =
  ## A flat complete-map calculation establishes root authority independently of cache or proof traversal.
  var entries: seq[StateEntry] = @[]
  for index in 0..<4: entries.add(StateEntry(key: key(Queries[index]), value: bytes(index)))
  let limits = FullStateTrieLimits(trie: StateTrieLimits(items: ElementLimit(8),
      perValue: ByteLimit(256),
    totalValueBytes: ByteLimit(512), nodes: TrieNodeLimit(10000)), writes: ElementLimit(8),
    writeValueBytes: ByteLimit(512))
  reset(0)
  let expected = stateTrieRoot(entries, limits.trie).value.root
  let trie = newFullStateTrie(entries, limits).value
  assert array[32, byte](trie.commitment.root) == array[32, byte](expected)
  trie
proc request(trie: FullStateTrie, number: int): LightStateProof =
  ## Detached producer output never grants cache authority until admission verifies it against the fixed root.
  LightStateProof(key: key(number), proof: trie.prove(key(number), policy().proof).value)
proc matches(cache: LightStateCache, known: array[8, bool], root: StateRoot) =
  ## Flat authored slots model local knowledge; complete-map membership alone never makes a slot known.
  var count = 0
  var total = 0'u64
  assert array[32, byte](cache.root) == array[32, byte](root)
  for index in 0..<Queries.len:
    let found = cache.lookup(key(Queries[index]))
    if known[index]:
      inc count
      assert found.error == LightCacheError.None
      let lookup = found.value
      assert array[32, byte](lookup.root) == array[32, byte](root)
      assert array[31, byte](lookup.key) == array[31, byte](key(Queries[index]))
      if index < 4:
        assert lookup.kind == StateLookupKind.Present and lookup.bytes == bytes(index)
        total += uint64(bytes(index).len)
      else:
        assert lookup.kind == StateLookupKind.Absent
    else:
      assert found.error == LightCacheError.UnknownKey
  assert cache.len == count and cache.valueBytes == total
proc semantics() =
  ## Admit unsorted positive/negative evidence, mutate caller/output bytes, then forget without changing retained views.
  let trie = fixture()
  let initial = newLightStateCache(trie.commitment.root, policy())
  var updates = @[request(trie, 250), request(trie, 64), request(trie, 0), request(trie, 192)]
  reset(0)
  let populated = initial.admit(updates).value
  var known = default(array[8, bool])
  for index in [0, 1, 3, 4]: known[index] = true
  matches(initial, default(array[8, bool]), trie.commitment.root)
  matches(populated, known, trie.commitment.root)
  assert populated.valueBytes == 289
  let retained = populated.lookup(key(0)).value
  updates[2].proof.value[0] = 99
  var copied = retained.bytes
  copied[0] = 88
  assert retained.bytes == bytes(0)
  reset(1)
  let forgotten = populated.forget([key(250), key(0), key(64)]).value
  assert calls() == 0
  matches(populated, known, trie.commitment.root)
  for index in [0, 1, 4]: known[index] = false
  matches(forgotten, known, trie.commitment.root)
  assert retained.bytes == bytes(0) and forgotten.valueBytes == 256
  let inherited = forgotten.limits
  assert uint64(inherited.items) == 8 and uint64(inherited.writes) == 8
  assert uint64(inherited.valueBytes) == 512 and uint64(inherited.proof.nodes) == 249
  assert uint64(inherited.proof.valueBytes) == 256
  let before = getOccupiedMem()
  let unchanged = forgotten.admit([]).value.forget([]).value
  assert getOccupiedMem() == before and unchanged.len == forgotten.len and calls() == 0
  assert populated.forget([key(7), key(7)]).error == LightCacheError.DuplicateKey
  assert populated.forget([key(7)]).value.len == populated.len and calls() == 0
proc boundaries() =
  ## Combined invalidities establish count/shape/duplicate/final-map precedence without hashing.
  let trie = fixture()
  let one = request(trie, 0)
  let empty = request(trie, 64)
  let absent = request(trie, 250)
  assert default(LightStateCache).lookup(key(0)).error == LightCacheError.Uninitialized
  assert default(LightStateCache).admit([]).error == LightCacheError.Uninitialized
  assert default(LightStateCache).forget([]).error == LightCacheError.Uninitialized
  for which in 0..<5:
    var limits = policy()
    case which
    of 0: limits.writes = ElementLimit(1)
    of 1: limits.items = ElementLimit(1)
    of 2: limits.valueBytes = ByteLimit(32)
    of 3: limits.proof.valueBytes = ByteLimit(32)
    else: limits.proof.nodes = ElementLimit(0)
    let cache = newLightStateCache(trie.commitment.root, limits)
    reset(1)
    assert cache.admit([one, empty]).error == LightCacheError.LimitExceeded and calls() == 0
    assert cache.len == 0 and cache.valueBytes == 0
  var tooMany = one
  tooMany.proof.nodes = newSeq[EncodedStateNode](250)
  var generous = policy()
  generous.proof.nodes = ElementLimit(high(uint64))
  reset(1)
  assert newLightStateCache(trie.commitment.root, generous).admit([tooMany]).error ==
      LightCacheError.LimitExceeded
  assert calls() == 0
  var limits = policy()
  limits.items = ElementLimit(0)
  reset(1)
  let zero = newLightStateCache(trie.commitment.root, limits)
  assert zero.admit([one, one]).error == LightCacheError.DuplicateKey and calls() == 0
  assert zero.admit([absent]).error == LightCacheError.LimitExceeded
  reset(0)
  limits = policy()
  limits.items = ElementLimit(2)
  limits.valueBytes = ByteLimit(33)
  let exact = newLightStateCache(trie.commitment.root, limits).admit([one]).value
  let replaced = exact.admit([empty, one]).value
  assert exact.len == 1 and replaced.len == 2 and replaced.valueBytes == 33
  reset(0)
  let large = request(trie, 192)
  assert exact.admit([large]).error == LightCacheError.LimitExceeded
  limits = policy()
  limits.valueBytes = ByteLimit(256)
  let smaller = newLightStateCache(trie.commitment.root, limits).admit([one]).value
  let freed = smaller.forget([key(0)]).value.admit([large]).value
  assert smaller.valueBytes == 33 and freed.valueBytes == 256
proc atomicity() =
  ## A valid first proof must not leak into the old snapshot when later evidence or hashing fails.
  let trie = fixture()
  let initial = newLightStateCache(trie.commitment.root, policy())
  let first = request(trie, 64)
  let second = request(trie, 0)
  var invalid = first
  invalid.proof.value = @[255'u8]
  reset(0)
  assert initial.admit([second, invalid]).error == LightCacheError.ValueMismatch
  assert initial.len == 0 and initial.lookup(key(64)).error == LightCacheError.UnknownKey
  var incomplete = second
  incomplete.proof.nodes.setLen(1)
  assert initial.admit([incomplete]).error == LightCacheError.IncompleteProof
  # Sorted key zero is verified first despite caller order; refuse in the second proof.
  refuseAfter(cint(second.proof.nodes.len+1))
  assert initial.admit([first, second]).error == LightCacheError.BackendFailure
  assert initial.len == 0 and initial.lookup(key(0)).error == LightCacheError.UnknownKey
  reset(0)
  let recovered = initial.admit([first, second]).value
  assert recovered.len == 2 and recovered.valueBytes == 33
  let changed = trie.apply([TrieWrite(key: key(250), kind: TrieWriteKind.Put, value: @[55'u8])]).value
  let negative = request(trie, 250)
  let newRoot = newLightStateCache(changed.commitment.root, policy())
  assert newRoot.lookup(key(250)).error == LightCacheError.UnknownKey
  assert newRoot.admit([negative]).error == LightCacheError.InvalidProof
  let refreshed = newRoot.admit([request(changed, 250)]).value
  assert refreshed.lookup(key(250)).value.bytes == @[55'u8]
  assert recovered.lookup(key(250)).error == LightCacheError.UnknownKey
proc sequence() =
  ## Deterministic finite known-key slots independently model batch merge/replacement and local forgetting.
  let trie = fixture()
  var current = newLightStateCache(trie.commitment.root, policy())
  var known = default(array[8, bool])
  for turn in 0..<25:
    let prior = current
    let oldKnown = known
    var updates: seq[LightStateProof] = @[]
    reset(0)
    for offset in 0..<3:
      let index = (turn+offset*3) mod 8
      updates.add(request(trie, Queries[index]))
      known[index] = true
    current = current.admit(updates).value
    let removed = (turn*5) mod 8
    reset(1)
    current = current.forget([key(Queries[removed])]).value
    assert calls() == 0
    known[removed] = false
    matches(current, known, trie.commitment.root)
    matches(prior, oldKnown, trie.commitment.root)
proc detached(): VerifiedStateLookup =
  ## Only a verified value survives retirement of source proofs, tries and every cache revision.
  let trie = fixture()
  let update = request(trie, 0)
  let initial = newLightStateCache(trie.commitment.root, policy())
  let populated = initial.admit([update]).value
  let retained = populated.lookup(key(0)).value
  assert populated.forget([key(0)]).value.lookup(key(0)).error == LightCacheError.UnknownKey
  retained
proc lifecycle() =
  ## Exact repeated owner retirement includes failed private proof scratch and retained detached values.
  atomicity()
  assert detached().bytes == bytes(0)
semantics()
boundaries()
atomicity()
sequence()
reset(1)
let empty = newLightStateCache(default(StateRoot), policy())
assert empty.lookup(key(0)).error == LightCacheError.UnknownKey
let negative = empty.admit([LightStateProof(key: key(0))]).value
assert negative.len == 1 and negative.lookup(key(0)).value.kind == StateLookupKind.Absent
assert negative.forget([key(0)]).value.lookup(key(0)).error == LightCacheError.UnknownKey
assert calls() == 0
lifecycle()
let before = getOccupiedMem()
for cycle in 0..<1000: lifecycle()
let after = getOccupiedMem()
assert before == after
recordArcRelease("storage_light_cache", 1000, before, after)
echo "PASS storage light cache: fixed-root knowledge, atomic proof batches, quotas, forgetting and retained views"
