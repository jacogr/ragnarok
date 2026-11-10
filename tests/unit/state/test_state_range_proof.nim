# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Independent complete-map roots authenticate range pages; boundary-only omissions and off-path witnesses fail.

import std/[assertions, syncio]
import ../../../src/state/[range_proof, trie_proof]
import ../../../src/codec/bounded
import ../../../src/codec/state/[layout, trie]

proc key(first: byte): StateKey =
  ## Distinct leading bytes expose both left truncated commitments and right full-width commitments.
  var raw = default(array[31, byte])
  raw[0] = first
  StateKey(raw)

proc policy(): StateTrieLimits =
  ## Small deterministic fixtures retain independent node, item and value ceilings.
  StateTrieLimits(items: ElementLimit(16), perValue: ByteLimit(256),
    totalValueBytes: ByteLimit(4096), nodes: TrieNodeLimit(4096))

proc witnesses(full: seq[StateEntry], start: StateKey, page: seq[StateEntry]): seq[
    EncodedStateNode] =
  ## Build root-to-start/last paths from the complete source, not the offered partial page.
  var queries = @[start]
  if page.len > 0: queries.add(page[^1].key)
  let generated = generateStateProofs(full, queries, policy(),
    StateProofLimits(nodes: ElementLimit(249), valueBytes: ByteLimit(256)),
    StateProofBatchLimits(items: ElementLimit(2), nodes: ElementLimit(498), valueBytes: ByteLimit(512)))
  assert generated.error == StateProofError.None
  result = @[]
  for ordinal in 0..<generated.value.len:
    let path = generated.value.queryAt(ordinal).value.proof
    for index in 0..<path.len:
      let node = path.nodeAt(index).value
      var duplicate = false
      for previous in result:
        if array[64, byte](previous) == array[64, byte](node): duplicate = true
      if not duplicate: result.add(node) # Preserve parent-before-child order while coalescing shared path nodes.

proc copied(source: seq[StateEntry]): seq[StateEntry] =
  ## Negative mutations never alter the trusted full mapping or a previously verified owner's private bytes.
  result = @[]
  for entry in source:
    var bytes: seq[byte] = @[]
    for octet in entry.value: bytes.add(octet)
    result.add(StateEntry(key: entry.key, value: bytes))

proc deepPrefixes() =
  ## Shared246-bit key prefixes exercise virtual singleton expansion at the key-depth boundary.
  for leading in [0'u8, 255'u8]:
    var full: seq[StateEntry] = @[]
    for index in 0..<4:
      var raw = default(array[31, byte])
      for offset in 0..<30: raw[offset] = leading
      raw[30] = byte(index)
      var value = newSeq[byte](11+index*17)
      for offset in 0..<value.len: value[offset] = byte(index+offset)
      full.add(StateEntry(key: StateKey(raw), value: value))
    let root = stateTrieRoot(full, policy()).value.root
    let start = full[0].key
    let finish = full[3].key
    let nodes = witnesses(full, start, full)
    let checked = verifyStateRange(full, nodes, root, start, finish, policy())
    assert checked.error == RangeProofError.None and checked.value.complete,
      "full range authenticates at maximum serialized-key depth in both root halves"
    let omitted = @[full[0], full[2], full[3]]
    assert verifyStateRange(omitted, nodes, root, start, finish, policy()).error ==
        RangeProofError.InvalidRange, "deep boundary proofs cannot hide an interior leaf"
    let prefix = @[full[0], full[1], full[2]]
    let partial = verifyStateRange(prefix, witnesses(full, start, prefix), root, start,
        finish, policy())
    assert partial.error == RangeProofError.None and not partial.value.complete,
      "deep partial ranges never inherit completeness from authenticated endpoints"

proc main() =
  ## Authentication checks every covered interior subtree rather than just the two endpoint lookups.
  var full: seq[StateEntry] = @[]
  for index in 1..6:
    var value = newSeq[byte](index*11)
    for offset in 0..<value.len: value[offset] = byte(index+offset)
    full.add(StateEntry(key: key(byte(index*16)), value: value))
  let root = stateTrieRoot(full, policy()).value.root
  let begin = key(0)
  let ending = key(255)
  let nodes = witnesses(full, begin, full)
  let all = verifyStateRange(full, nodes, root, begin, ending, policy())
  assert all.error == RangeProofError.None, "complete source authenticates all range interior commitments"
  assert all.value.valid and all.value.len == full.len and all.value.complete
  assert array[32, byte](all.value.root) == array[32, byte](root)
  assert array[31, byte](all.value.start) == array[31, byte](begin)
  assert array[31, byte](all.value.finish) == array[31, byte](ending)
  for index in 0..<full.len:
    assert array[31, byte](all.value.keyAt(index)) == array[31, byte](full[index].key)
    assert all.value.valueAt(index) == full[index].value
  var extracted = all.value.valueAt(0)
  extracted[0] = 255
  assert all.value.valueAt(0) == full[0].value
  var prefix = @[full[0], full[1], full[2]]
  let shorter = verifyStateRange(prefix, witnesses(full, begin, prefix), root, begin, ending,
      policy())
  assert shorter.error == RangeProofError.None and not shorter.value.complete
  var omitted = @[full[0], full[2], full[3], full[4], full[5]]
  assert verifyStateRange(omitted, nodes, root, begin, ending, policy()).error ==
      RangeProofError.InvalidRange,
    "valid endpoint proofs cannot authenticate an omitted interior pair"
  var changed = copied(full)
  changed[2].value[0] = changed[2].value[0] xor 1
  assert verifyStateRange(changed, nodes, root, begin, ending, policy()).error ==
      RangeProofError.InvalidRange,
    "interior value hashes are bound even when absent from both supplied boundary paths"
  let missingFirst = @[full[1], full[2], full[3], full[4], full[5]]
  assert verifyStateRange(missingFirst, witnesses(full, full[0].key, full), root,
    full[0].key, ending, policy()).error != RangeProofError.None
  let middle = @[full[1], full[2], full[3], full[4]]
  let interior = verifyStateRange(middle, witnesses(full, key(21), middle), root, key(21), key(80),
      policy())
  assert interior.error == RangeProofError.None and interior.value.complete, "absent inclusive start still authenticates the contiguous range"
  let one = @[full[2]]
  let single = verifyStateRange(one, witnesses(full, one[0].key, one), root, one[0].key, ending,
      policy())
  assert single.error == RangeProofError.None and not single.value.complete
  let empty: seq[StateEntry] = @[]
  let absent = verifyStateRange(empty, witnesses(full, begin, empty), root, begin, key(5), policy())
  assert absent.error == RangeProofError.None and absent.value.complete and absent.value.len == 0
  let uncertain = verifyStateRange(empty, witnesses(full, key(21), empty), root, key(21), ending,
      policy())
  assert uncertain.error == RangeProofError.None and not uncertain.value.complete,
    "start absence alone never proves the requested range contains no later keys"
  let emptyRoot = stateTrieRoot(empty, policy()).value.root
  let zero = verifyStateRange(empty, [], emptyRoot, begin, ending, policy())
  assert zero.error == RangeProofError.None and zero.value.complete
  var duplicate: seq[EncodedStateNode] = @[]
  for node in nodes: duplicate.add(node)
  duplicate.add(nodes[0])
  assert verifyStateRange(full, duplicate, root, begin, ending, policy()).error ==
      RangeProofError.InvalidProof
  var reversed: seq[EncodedStateNode] = @[]
  assert nodes.len >= 2
  reversed.add(nodes[1])
  reversed.add(nodes[0])
  for index in 2..<nodes.len: reversed.add(nodes[index])
  assert verifyStateRange(full, reversed, root, begin, ending, policy()).error ==
      RangeProofError.InvalidProof
  var extra: seq[EncodedStateNode] = @[]
  for node in nodes: extra.add(node)
  extra.add(encodeStateLeaf(full[2].key, full[2].value, ByteLimit(256)).value)
  assert verifyStateRange(full, extra, root, begin, ending, policy()).error ==
      RangeProofError.InvalidProof
  var wrong = array[32, byte](root)
  wrong[0] = wrong[0] xor 1
  assert verifyStateRange(full, nodes, StateRoot(wrong), begin, ending, policy()).error ==
      RangeProofError.RootMismatch
  var limited = policy()
  limited.items = ElementLimit(1)
  assert verifyStateRange(full, nodes, root, begin, ending, limited).error ==
      RangeProofError.LimitExceeded
  assert verifyStateRange(full, nodes, root, ending, begin, policy()).error ==
      RangeProofError.InvalidRange
  deepPrefixes()
  echo "state range proof: trusted boundaries and all interior commitments verified"
main()
