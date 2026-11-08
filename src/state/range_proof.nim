# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Authenticate a contiguous serialized-state page against an independent complete root.
## Page evidence retains copied values, never a complete-map owner or adoption/finality authority.

import std/assertions
import ./trie_proof
import ../codec/bounded
import ../codec/state/[layout, trie]

type
  RangeProofError* {.pure.} = enum ## Default/failed verification carries no authenticated page prefix.
    Uninitialized, None, InvalidConfig, LimitExceeded, InvalidRange, InvalidProof,
    RootMismatch, BackendFailure
  RangeData = ref object ## Immutable acyclic page ownership is separate from a full StateStore.
    root: StateRoot
    start, finish: StateKey
    complete: bool
    entries: seq[StateEntry]
  VerifiedStateRange* = object ## Only a trusted-root verifier can create this immutable partial-state evidence.
    data: nil RangeData
  RangeProofResult* = object ## A successful tag alone grants a complete private page owner.
    case status: RangeProofError
    of None: completed: VerifiedStateRange
    else: discard            # Failure never exposes a subset of authenticated pairs.
  Edge = object ## Left edges commit255 bits; their discarded high bit is never guessed.
    digest: array[32, byte]
    partial: bool
  NodeFact = object ## One canonical encoded node is hashed once into detached fixed metadata.
    wire: EncodedStateNode
    digest: array[32, byte]
    info: StateNodeInfo
  NodeMap = object ## Tiny bounded node maps preserve wire ordinals for topology/unused-node validation.
    facts: seq[NodeFact]
    used: seq[bool]
  Children = object ## Empty and singleton subtrees can be compared without inventing serialized GP branch nodes.
    left, right: Edge
  Match {.pure.} = enum ## Unknown opaque boundaries can never prove requested-end completeness.
    Equal, Different, Unknown

func error*(outcome: RangeProofResult): RangeProofError =
  ## Inspect only the private failure/success tag.
  outcome.status

func value*(outcome: RangeProofResult): VerifiedStateRange {.requires: outcome.status ==
    RangeProofError.None.} =
  ## Extract a whole immutable verified page, not a successful prefix from a later failure.
  outcome.completed

func valid*(page: VerifiedStateRange): bool =
  ## Default pages contain neither root authority nor values.
  page.data != nil

func len*(page: VerifiedStateRange): int =
  ## An authenticated empty page differs from the default through valid, not count alone.
  let data = page.data
  if data == nil: 0 else: data.entries.len

proc checkedData(page: VerifiedStateRange): RangeData {.requires: page.valid.} =
  ## Refine one stable borrowed reference after its public validity guard.
  let data = page.data
  assert data != nil
  data

proc root*(page: VerifiedStateRange): StateRoot {.requires: page.valid.} =
  ## This independent complete root authenticates partial evidence; it is never recomputed from this page.
  page.checkedData.root

proc start*(page: VerifiedStateRange): StateKey {.requires: page.valid.} =
  ## Root and query bounds remain bound to the same immutable page owner.
  page.checkedData.start

proc finish*(page: VerifiedStateRange): StateKey {.requires: page.valid.} =
  ## Completion refers only to this requested end, never the entire key space implicitly.
  page.checkedData.finish

proc complete*(page: VerifiedStateRange): bool {.requires: page.valid.} =
  ## True only when the boundary evidence proves no omitted keys through the requested end.
  page.checkedData.complete

proc keyAt*(page: VerifiedStateRange, index: int): StateKey {.requires: page.valid and index >=
    0 and index < page.len.} =
  ## Owner-bound ordinals return fixed copied serialized keys.
  page.checkedData.entries[index].key

proc valueAt*(page: VerifiedStateRange, index: int): seq[byte] {.requires: page.valid and index >=
    0 and index < page.len.} =
  ## Copies cannot mutate the page's privately retained values.
  let data = page.checkedData
  result = @[]
  for offset in 0..<data.entries[index].value.len:
    result.add(data.entries[index].value[offset]) # Index the immutable owner; do not take an iterator borrow through a ref.

func compare(left, right: StateKey): int =
  ## MSB-first lexicographic order is the trie partition order.
  let a = array[31, byte](left)
  let b = array[31, byte](right)
  for index in 0..<31:
    if a[index] < b[index]: return -1
    if a[index] > b[index]: return 1
  0

func bit(key: StateKey, depth: int): bool {.requires: depth >= 0 and depth < 248.} =
  ## Callers prove the maximum serialized-key depth before accessing a byte or shift.
  (array[31, byte](key)[depth div 8] and byte(128 shr (depth mod 8))) != 0

func matches(left, right: Edge): bool =
  ## Compare exactly the committed width, including when the other tree has a virtual singleton leaf.
  var a = left.digest
  var b = right.digest
  if left.partial or right.partial:
    a[0] = a[0] and 127
    b[0] = b[0] and 127
  a == b

proc add(map: var NodeMap, wire: EncodedStateNode, strict: bool): RangeProofError =
  ## Protocol witnesses forbid duplicates; internally generated intersecting paths coalesce exact bytes.
  for fact in map.facts:
    if array[64, byte](fact.wire) == array[64, byte](wire):
      return if strict: RangeProofError.InvalidProof else: RangeProofError.None
  if map.facts.len >= 512: return RangeProofError.LimitExceeded
  let decoded = decodeStateNode(array[64, byte](wire))
  if decoded.error != StateLayoutError.None: return RangeProofError.InvalidProof
  let hashed = hashStateNode(wire)
  if hashed.error != StateLayoutError.None: return RangeProofError.BackendFailure
  map.facts.add(NodeFact(wire: wire, digest: array[32, byte](hashed.value),
      info: decoded.value.node))
  map.used.add(false)
  RangeProofError.None

proc find(map: NodeMap, edge: Edge): int =
  ## Zero is an empty subtree; ambiguous masked matches are rejected without reconstructing a lost bit.
  if edge.digest == default(array[32, byte]): return -2
  result = -1
  for index in 0..<map.facts.len:
    var actual = map.facts[index].digest
    if edge.partial: actual[0] = actual[0] and 127
    if actual == edge.digest:
      if result >= 0: return -3
      result = index

proc boundary(map: var NodeMap, expected: StateRoot, query: StateKey,
    supplied: openArray[byte], present: bool, perValue: ByteLimit): RangeProofError =
  ## Resolve one root-first path, then reuse the existing independent-root GP lookup verifier.
  var path: seq[EncodedStateNode] = @[]
  var edge = Edge(digest: array[32, byte](expected))
  var previous = -1
  var depth = 0
  while true:
    let index = map.find(edge)
    if index == -2: break # A zero selected edge terminates an absence witness after its parent branch.
    if index < 0:
      return if previous < 0 and index != -3: RangeProofError.RootMismatch else: RangeProofError.InvalidProof
    if index <= previous: return RangeProofError.InvalidProof
    if path.len >= 249: return RangeProofError.InvalidProof
    previous = index
    map.used[index] = true
    path.add(map.facts[index].wire)
    let info = map.facts[index].info
    if info.kind != StateNodeKind.Branch: break
    if depth >= 248: return RangeProofError.InvalidProof
    edge = if query.bit(depth): Edge(digest: array[32, byte](info.right))
      else: Edge(digest: array[32, byte](info.left), partial: true)
    inc depth
  let limits = StateProofLimits(nodes: ElementLimit(249), valueBytes: perValue)
  let captured = captureStateProof(path, supplied, limits)
  if captured.error != StateProofError.None: return RangeProofError.InvalidProof
  let checked = verifyStateProof(captured.value, expected, query, limits)
  if checked.error == StateProofError.BackendFailure: return RangeProofError.BackendFailure
  if checked.error == StateProofError.RootMismatch: return RangeProofError.RootMismatch
  if checked.error != StateProofError.None: return RangeProofError.InvalidProof
  if checked.value.present != present: return RangeProofError.InvalidRange
  RangeProofError.None

proc children(map: NodeMap, edge: Edge, depth: int, output: var Children): bool =
  ## A singleton's depth-independent leaf hash follows its own key through virtual comparison branches only.
  output = default(Children)
  let index = map.find(edge)
  if index == -2: return true
  if index < 0 or depth >= 248: return false
  let fact = map.facts[index]
  let info = fact.info
  if info.kind == StateNodeKind.Branch:
    output.left = Edge(digest: array[32, byte](info.left), partial: true)
    output.right = Edge(digest: array[32, byte](info.right))
  else:
    let key = if info.kind == StateNodeKind.EmbeddedLeaf: info.embeddedKey else: info.hashedKey
    let child = Edge(digest: fact.digest)
    if key.bit(depth): output.right = child
    else: output.left = child
  true

proc covered(auth, page: NodeMap, a, b: Edge, lower, upper, start, finish: StateKey,
    depth: int): Match =
  ## Only two boundary prefixes remain partial at each depth; wholly covered subtrees compare commitments directly.
  if compare(upper, start) < 0 or compare(lower, finish) > 0: return Match.Equal
  if compare(lower, start) >= 0 and compare(upper, finish) <= 0:
    return if matches(a, b): Match.Equal else: Match.Different
  if depth >= 248: return Match.Unknown
  var left = default(Children)
  var right = default(Children)
  if not auth.children(a, depth, left) or not page.children(b, depth, right): return Match.Unknown
  var leftUpper = array[31, byte](upper)
  var rightLower = array[31, byte](lower)
  let mask = byte(128 shr (depth mod 8))
  leftUpper[depth div 8] = leftUpper[depth div 8] and not mask
  rightLower[depth div 8] = rightLower[depth div 8] or mask
  let first = covered(auth, page, left.left, right.left, lower, StateKey(leftUpper), start, finish, depth+1)
  if first == Match.Different: return first
  let second = covered(auth, page, left.right, right.right, StateKey(rightLower), upper, start,
      finish, depth+1)
  if second == Match.Different: return second
  if first == Match.Unknown or second == Match.Unknown: Match.Unknown else: Match.Equal

func validRangeLimits*(limits: StateTrieLimits): bool =
  ## Small independent comparisons keep every work/byte ceiling explicit before hashing or allocation.
  if uint64(limits.items) == 0: return false
  if uint64(limits.items) > 16384: return false
  if uint64(limits.perValue) > 4194304: return false
  if uint64(limits.totalValueBytes) > 8388608: return false
  if uint64(limits.nodes) == 0: return false
  uint64(limits.nodes) <= 1048576

proc verifyStateRange*(entries: openArray[StateEntry], nodes: openArray[EncodedStateNode],
    expected: StateRoot, start, finish: StateKey, limits: StateTrieLimits): RangeProofResult =
  ## Authenticate boundary membership/absence and every covered interior subtree before freezing a private page.
  if not validRangeLimits(limits):
    return RangeProofResult(status: RangeProofError.InvalidConfig)
  if entries.len > 16384 or uint64(entries.len) > uint64(limits.items) or nodes.len > 512:
    return RangeProofResult(status: RangeProofError.LimitExceeded)
  if compare(start, finish) > 0: return RangeProofResult(status: RangeProofError.InvalidRange)
  var bytes = 0'u64
  for index, entry in entries:
    if uint64(entry.value.len) > uint64(limits.perValue) or uint64(entry.value.len) > uint64(
        limits.totalValueBytes)-bytes:
      return RangeProofResult(status: RangeProofError.LimitExceeded)
    bytes += uint64(entry.value.len)
    if compare(entry.key, start) < 0 or compare(entry.key, finish) > 0:
      return RangeProofResult(status: RangeProofError.InvalidRange)
    if index > 0 and compare(entries[index-1].key, entry.key) >= 0:
      return RangeProofResult(status: RangeProofError.InvalidRange)
  var auth = default(NodeMap)
  for node in nodes:
    let added = auth.add(node, true)
    if added != RangeProofError.None: return RangeProofResult(status: added)
  let startsPresent = entries.len > 0 and compare(entries[0].key, start) == 0
  let checkedStart = if startsPresent: auth.boundary(expected, start, entries[0].value, true,
      limits.perValue)
    else: auth.boundary(expected, start, [], false, limits.perValue)
  if checkedStart != RangeProofError.None: return RangeProofResult(status: checkedStart)
  if entries.len > 0:
    let checkedLast = auth.boundary(expected, entries[^1].key, entries[^1].value, true,
        limits.perValue)
    if checkedLast != RangeProofError.None: return RangeProofResult(status: checkedLast)
  for used in auth.used:
    if not used: return RangeProofResult(status: RangeProofError.InvalidProof) # Extra/off-path nodes cannot smuggle an alternative interior witness.
  var page = default(NodeMap)
  var pageRoot = default(Edge)
  if entries.len > 0:
    let paths = generateStateProofs(entries, [start, entries[^1].key], limits,
      StateProofLimits(nodes: ElementLimit(249), valueBytes: limits.perValue),
      StateProofBatchLimits(items: ElementLimit(2), nodes: ElementLimit(498), valueBytes: ByteLimit(8388608)))
    if paths.error == StateProofError.LimitExceeded or paths.error ==
        StateProofError.LengthOverflow:
      return RangeProofResult(status: RangeProofError.LimitExceeded)
    if paths.error != StateProofError.None: return RangeProofResult(
        status: RangeProofError.BackendFailure)
    for query in 0..<paths.value.len:
      let proof = paths.value.queryAt(query).value.proof
      for index in 0..<proof.len:
        let added = page.add(proof.nodeAt(index).value, false)
        if added != RangeProofError.None: return RangeProofResult(status: added)
    if page.facts.len == 0: return RangeProofResult(status: RangeProofError.InvalidProof)
    pageRoot = Edge(digest: page.facts[0].digest)
  let authRoot = Edge(digest: array[32, byte](expected))
  let lower = default(StateKey)
  var upperBytes = default(array[31, byte])
  for index in 0..<31: upperBytes[index] = 255
  let upper = StateKey(upperBytes)
  if entries.len > 0:
    let matched = covered(auth, page, authRoot, pageRoot, lower, upper, start, entries[^1].key, 0)
    if matched != Match.Equal: return RangeProofResult(
        status: RangeProofError.InvalidRange) # Boundary lookups alone cannot authorize omitted interior pairs.
  let complete = covered(auth, page, authRoot, pageRoot, lower, upper, start, finish, 0) == Match.Equal
  var frozen = newSeq[StateEntry](entries.len)
  for index, entry in entries:
    var value = newSeq[byte](entry.value.len)
    for offset, octet in entry.value: value[offset] = octet
    frozen[index] = StateEntry(key: entry.key, value: value)
  RangeProofResult(status: RangeProofError.None, completed: VerifiedStateRange(
    data: RangeData(root: expected, start: start, finish: finish, complete: complete,
        entries: frozen)))
