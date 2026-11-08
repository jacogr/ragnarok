# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bounded GP N/T/WB trace construction and exact NP node representation support for availability data.
## These computations authenticate only against a caller-selected root; canonical report authority is a separate boundary.

import ../codec/bounded
import ../crypto/primitives

const
  AvailabilityTreeLeaves* = 3120 ## At most 3072 exports plus 48 proof pages.
  AvailabilityLeafBytes* = 1368  ## Six-validator geometry has the largest segment shard.
  AvailabilityTraceDepth* = 12   ## ceil(log2(3120)); validator traces need at most ten.
  NodePreimageBytes = 4+AvailabilityLeafBytes*2

type
  AvailabilityMerkleError* {.pure.} = enum ## Failures carry reasons only; no partial trace or root escapes.
    Uninitialized, None, InvalidInput, InvalidIndex, InvalidProof, LimitExceeded, RootMismatch, BackendFailure
  AvailabilityMerkleLimits* = object ## Logical flat-input/output and complete primitive work have independent ceilings.
    bytes*, hashBytes*: ByteLimit
    hashes*: ElementLimit
  AvailabilityMerkleResult*[T] = object ## Private selected payloads preserve genuine crypto failure and successful complete outputs.
    case status: AvailabilityMerkleError
    of None: completed: T
    of BackendFailure: cryptoReason: CryptoError
    else: discard # Default/simple failure alternatives contain no accepted prefix or unrelated child.
  AvailabilityMerkleWork* = object ## Exact bounded work facts permit aggregate precharge before composing multiple proof stages.
    payloadBytes*, proofBytes*, hashes*, hashBytes*: uint64
  AvailabilityTrace* = object ## Detached encoded root-first siblings and derived root contain no source graph or native handle.
    ready: bool
    root: Blake2bHash
    wire: seq[byte]
  NodeValue = object ## Fixed scratch holds either one bounded raw leaf or one hash; it never crosses the public API.
    length: int
    bytes: array[AvailabilityLeafBytes, byte]
  HashBudget = object ## Private counters prove every charge before arithmetic and every maintained primitive call.
    maximum: AvailabilityMerkleLimits
    calls, bytes: uint64
  TraceStep = object ## Root-first shape is derived solely from validated count/index, never an untrusted tag.
    left: bool
    tag: byte
    width, first, count, offset: int
  TraceShape = object ## Fixed path capacity follows the public hard leaf-count bound.
    steps: array[AvailabilityTraceDepth, TraceStep]
    count, bytes: int

func error*[T](outcome: AvailabilityMerkleResult[T]): AvailabilityMerkleError =
  ## Inspect a reason without exposing writable result storage.
  outcome.status

func value*[T](outcome: AvailabilityMerkleResult[T]): T {.requires: outcome.status ==
    AvailabilityMerkleError.None.} =
  ## Only complete success exposes its payload.
  outcome.completed

func cryptoError*[T](outcome: AvailabilityMerkleResult[
    T]): CryptoError {.requires: outcome.status == AvailabilityMerkleError.BackendFailure.} =
  ## Preserve only a genuine failed maintained Blake2b call.
  outcome.cryptoReason

func failed[T](reason: AvailabilityMerkleError): AvailabilityMerkleResult[T] {.requires:
    reason notin {AvailabilityMerkleError.None, AvailabilityMerkleError.BackendFailure}.} =
  ## Construct simple/default reason-only alternatives, never a success or invented crypto child.
  AvailabilityMerkleResult[T](status: reason)

func propagated[T, U](outcome: AvailabilityMerkleResult[U]): AvailabilityMerkleResult[T] {.requires:
    outcome.status != AvailabilityMerkleError.None.} =
  ## Converting failed scratch/result types preserves the selected cause without retaining successful data.
  if outcome.status == AvailabilityMerkleError.BackendFailure:
    return AvailabilityMerkleResult[T](status: AvailabilityMerkleError.BackendFailure,
        cryptoReason: outcome.cryptoReason)
  failed[T](outcome.status)

func valid*(trace: AvailabilityTrace): bool =
  ## A default trace is distinct from a genuine singleton's successful empty proof.
  trace.ready

func root*(trace: AvailabilityTrace): Blake2bHash {.requires: trace.ready.} =
  ## A copied computed root is a commitment, not canonical availability authority.
  trace.root

proc bytes*(trace: AvailabilityTrace): seq[byte] {.requires: trace.ready.} =
  ## Returned proof bytes are independent of retained trace storage.
  result = newSeq[byte](trace.wire.len)
  for index in 0..<result.len: result[index] = trace.wire[index]

proc hashed(bytes: openArray[byte], budget: var HashBudget): AvailabilityMerkleResult[Blake2bHash] =
  ## Charge before the call and before addition, retaining the exact backend refusal on failure.
  if budget.calls >= uint64(budget.maximum.hashes): return failed[Blake2bHash](
      AvailabilityMerkleError.LimitExceeded)
  if uint64(bytes.len) > uint64(budget.maximum.hashBytes)-budget.bytes:
    return failed[Blake2bHash](AvailabilityMerkleError.LimitExceeded)
  inc budget.calls
  budget.bytes += uint64(bytes.len)
  let digest = blake2b256(bytes)
  if digest.error != CryptoError.None:
    return AvailabilityMerkleResult[Blake2bHash](status: AvailabilityMerkleError.BackendFailure,
        cryptoReason: digest.error)
  AvailabilityMerkleResult[Blake2bHash](status: AvailabilityMerkleError.None,
      completed: digest.value)

func validShape(width, count: int): bool =
  ## Bound factors independently before any caller forms their native product.
  width > 0 and width <= AvailabilityLeafBytes and count >= 0 and count <= AvailabilityTreeLeaves

proc shape(width, count, index: int, leafTag: byte): AvailabilityMerkleResult[TraceShape] =
  ## Derive ceil/floor siblings, raw-versus-hash tags and offsets without reading any peer bytes.
  if not validShape(width, count): return failed[TraceShape](AvailabilityMerkleError.InvalidInput)
  if index < 0 or index >= count: return failed[TraceShape](AvailabilityMerkleError.InvalidIndex)
  if leafTag notin [1'u8, 2]: return failed[TraceShape](AvailabilityMerkleError.InvalidInput)
  if leafTag == 1 and width != 64: return failed[TraceShape](AvailabilityMerkleError.InvalidInput)
  var path = default(TraceShape)
  var first = 0
  var remaining = count
  var selected = index
  while remaining > 1:
    # Count <=3120 proves addition and path capacity before recording each step.
    if path.count >= AvailabilityTraceDepth: return failed[TraceShape](
        AvailabilityMerkleError.InvalidInput)
    let left = (remaining+1) div 2
    let goesLeft = selected < left
    let siblingFirst = if goesLeft: first+left else: first
    let siblingCount = if goesLeft: remaining-left else: left
    let size = if siblingCount == 1: width else: 32
    let tag = if siblingCount == 1: leafTag else: 0'u8
    path.steps[path.count] = TraceStep(left: goesLeft, tag: tag, width: size,
      first: siblingFirst, count: siblingCount, offset: path.bytes)
    inc path.count
    path.bytes += 1+size
    if goesLeft:
      remaining = left
    else:
      first += left
      selected -= left
      remaining -= left
  AvailabilityMerkleResult[TraceShape](status: AvailabilityMerkleError.None, completed: path)

proc rawLeaf(flat: openArray[byte], width, index: int): NodeValue =
  ## Callers proved the complete flat extent and coordinate before forming this bounded offset.
  result = default(NodeValue)
  result.length = width
  let first = index*width
  for position in 0..<width: result.bytes[position] = flat[first+position]

proc node(flat: openArray[byte], width, first, count: int,
    budget: var HashBudget): AvailabilityMerkleResult[NodeValue] =
  ## GP N returns a raw singleton child; only non-singleton subtrees hash the node-prefixed concatenation.
  if count == 1:
    return AvailabilityMerkleResult[NodeValue](status: AvailabilityMerkleError.None,
        completed: rawLeaf(flat, width, first))
  let leftCount = (count+1) div 2
  let left = node(flat, width, first, leftCount, budget)
  if left.error != AvailabilityMerkleError.None: return left
  let right = node(flat, width, first+leftCount, count-leftCount, budget)
  if right.error != AvailabilityMerkleError.None: return right
  let a = left.value
  let b = right.value
  var preimage = default(array[NodePreimageBytes, byte])
  preimage[0] = byte('n')
  preimage[1] = byte('o')
  preimage[2] = byte('d')
  preimage[3] = byte('e')
  var used = 4
  for position in 0..<a.length:
    preimage[used] = a.bytes[position]
    inc used
  for position in 0..<b.length:
    preimage[used] = b.bytes[position]
    inc used
  let digest = hashed(preimage.toOpenArray(0, used-1), budget)
  if digest.error != AvailabilityMerkleError.None: return propagated[NodeValue, Blake2bHash](digest)
  var completed = default(NodeValue)
  completed.length = 32
  let bytes = array[32, byte](digest.value)
  for position in 0..<32: completed.bytes[position] = bytes[position]
  AvailabilityMerkleResult[NodeValue](status: AvailabilityMerkleError.None, completed: completed)

proc fold(leaf: openArray[byte], proof: openArray[byte], path: TraceShape,
    budget: var HashBudget): AvailabilityMerkleResult[Blake2bHash] =
  ## Validate every expected tag/extent first, then reconstruct from the raw leaf upward through root-first trace storage.
  if proof.len != path.bytes: return failed[Blake2bHash](AvailabilityMerkleError.InvalidProof)
  for index in 0..<path.count:
    if proof[path.steps[index].offset] != path.steps[index].tag:
      return failed[Blake2bHash](AvailabilityMerkleError.InvalidProof)
  if path.count == 0: return hashed(leaf, budget) # WB hashes the sole whole-tree leaf; N's internal singleton remains raw.
  var current = default(NodeValue)
  current.length = leaf.len
  for position in 0..<leaf.len: current.bytes[position] = leaf[position]
  var index = path.count
  while index > 0:
    # Reverse traversal consumes already validated node payloads; every concatenation fits 4+2*1368 scratch bytes.
    dec index
    let step = path.steps[index]
    var preimage = default(array[NodePreimageBytes, byte])
    preimage[0] = byte('n')
    preimage[1] = byte('o')
    preimage[2] = byte('d')
    preimage[3] = byte('e')
    var used = 4
    for side in 0..<2:
      let takeCurrent = (side == 0) == step.left
      let size = if takeCurrent: current.length else: step.width
      for position in 0..<size:
        preimage[used] = if takeCurrent: current.bytes[position] else: proof[step.offset+1+position]
        inc used
    let digest = hashed(preimage.toOpenArray(0, used-1), budget)
    if digest.error != AvailabilityMerkleError.None: return digest
    current.length = 32
    let bytes = array[32, byte](digest.value)
    for position in 0..<32: current.bytes[position] = bytes[position]
  var bytes = default(array[32, byte])
  for position in 0..<32: bytes[position] = current.bytes[position]
  AvailabilityMerkleResult[Blake2bHash](status: AvailabilityMerkleError.None,
      completed: Blake2bHash(bytes))

proc prepareAvailabilityTrace*(flat: openArray[byte], width, count, index: int,
    leafTag: byte, limits: AvailabilityMerkleLimits): AvailabilityMerkleResult[AvailabilityTrace] =
  ## Exact flat geometry and complete input/output charge precede extraction; tracing never trusts peer-supplied node tags.
  let planned = shape(width, count, index, leafTag)
  if planned.error != AvailabilityMerkleError.None: return propagated[AvailabilityTrace,
      TraceShape](planned)
  let path = planned.value
  let extent = count*width # Validated factors bound this below 4.3 MiB before multiplication.
  if flat.len != extent: return failed[AvailabilityTrace](AvailabilityMerkleError.InvalidInput)
  if uint64(extent)+uint64(path.bytes) > uint64(limits.bytes): return failed[AvailabilityTrace](
      AvailabilityMerkleError.LimitExceeded)
  var budget = HashBudget(maximum: limits, calls: 0, bytes: 0)
  var wire = newSeq[byte](path.bytes)
  for index in 0..<path.count:
    # Opposite subtrees are disjoint, so full trace construction and root reconstruction do at most the whole tree's hash work.
    let step = path.steps[index]
    let sibling = node(flat, width, step.first, step.count, budget)
    if sibling.error != AvailabilityMerkleError.None: return propagated[AvailabilityTrace,
        NodeValue](sibling)
    wire[step.offset] = step.tag
    let selected = sibling.value
    for position in 0..<step.width: wire[step.offset+1+position] = selected.bytes[position]
  let selected = rawLeaf(flat, width, index)
  let computed = fold(selected.bytes.toOpenArray(0, width-1), wire, path, budget)
  if computed.error != AvailabilityMerkleError.None: return propagated[AvailabilityTrace,
      Blake2bHash](computed)
  AvailabilityMerkleResult[AvailabilityTrace](status: AvailabilityMerkleError.None,
    completed: AvailabilityTrace(ready: true, root: computed.value, wire: wire))

proc reconstructAvailabilityTrace*(leaf, proof: openArray[byte], width, count, index: int,
    leafTag: byte, limits: AvailabilityMerkleLimits): AvailabilityMerkleResult[Blake2bHash] =
  ## Reconstruct a root proposal from exact structure; only a later comparison with independently selected authority authenticates it.
  let planned = shape(width, count, index, leafTag)
  if planned.error != AvailabilityMerkleError.None: return propagated[Blake2bHash, TraceShape](planned)
  if leaf.len != width: return failed[Blake2bHash](AvailabilityMerkleError.InvalidInput)
  if uint64(leaf.len)+uint64(proof.len) > uint64(limits.bytes): return failed[Blake2bHash](
      AvailabilityMerkleError.LimitExceeded)
  var budget = HashBudget(maximum: limits, calls: 0, bytes: 0)
  fold(leaf, proof, planned.value, budget)

proc verifyAvailabilityTrace*(expected: Blake2bHash, leaf, proof: openArray[byte],
    width, count, index: int, leafTag: byte,
    limits: AvailabilityMerkleLimits): AvailabilityMerkleResult[Blake2bHash] =
  ## The trusted root and exact coordinates are independent inputs; no rejected path exposes an authenticated prefix.
  let computed = reconstructAvailabilityTrace(leaf, proof, width, count, index, leafTag, limits)
  if computed.error != AvailabilityMerkleError.None: return computed
  if array[32, byte](computed.value) != array[32, byte](expected): return failed[Blake2bHash](
      AvailabilityMerkleError.RootMismatch)
  computed

proc availabilityMerkleRoot*(flat: openArray[byte], width, count: int,
    limits: AvailabilityMerkleLimits): AvailabilityMerkleResult[Blake2bHash] =
  ## GP WB has an all-zero empty root and hashes a singleton whole-tree leaf without the node prefix.
  if not validShape(width, count): return failed[Blake2bHash](AvailabilityMerkleError.InvalidInput)
  let extent = width*count
  if flat.len != extent: return failed[Blake2bHash](AvailabilityMerkleError.InvalidInput)
  if uint64(extent) > uint64(limits.bytes): return failed[Blake2bHash](
      AvailabilityMerkleError.LimitExceeded)
  if count == 0:
    return AvailabilityMerkleResult[Blake2bHash](status: AvailabilityMerkleError.None,
      completed: Blake2bHash(default(array[32, byte])))
  var budget = HashBudget(maximum: limits, calls: 0, bytes: 0)
  if count == 1: return hashed(flat, budget)
  let computed = node(flat, width, 0, count, budget)
  if computed.error != AvailabilityMerkleError.None: return propagated[Blake2bHash, NodeValue](computed)
  var root = default(array[32, byte])
  for position in 0..<32: root[position] = computed.value.bytes[position]
  AvailabilityMerkleResult[Blake2bHash](status: AvailabilityMerkleError.None,
      completed: Blake2bHash(root))

proc availabilityTreeWork*(width, count: int): AvailabilityMerkleResult[AvailabilityMerkleWork] =
  ## GP WB counts every raw leaf byte, node prefix and hashed-child edge exactly once.
  if not validShape(width, count): return failed[AvailabilityMerkleWork](
      AvailabilityMerkleError.InvalidInput)
  let n = uint64(count)
  let w = uint64(width)
  var work = AvailabilityMerkleWork(payloadBytes: n*w)
  if count == 1:
    work.hashes = 1
    work.hashBytes = w
  elif count > 1:
    work.hashes = n-1
    work.hashBytes = n*w+4*(n-1)+32*(n-2)
  AvailabilityMerkleResult[AvailabilityMerkleWork](status: AvailabilityMerkleError.None,
      completed: work)

proc availabilityTraceWork*(width, count, index: int,
    leafTag: byte): AvailabilityMerkleResult[AvailabilityMerkleWork] =
  ## Verification work follows the selected path only; construction additionally hashes opposite subtrees using whole-tree work.
  let planned = shape(width, count, index, leafTag)
  if planned.error != AvailabilityMerkleError.None: return propagated[AvailabilityMerkleWork,
      TraceShape](planned)
  let path = planned.value
  var work = AvailabilityMerkleWork(payloadBytes: uint64(width+path.bytes), proofBytes: uint64(path.bytes))
  if path.count == 0:
    work.hashes = 1
    work.hashBytes = uint64(width)
  else:
    var selectedWidth = width
    var index = path.count
    while index > 0:
      dec index
      inc work.hashes
      work.hashBytes += uint64(4+selectedWidth+path.steps[index].width)
      selectedWidth = 32
  AvailabilityMerkleResult[AvailabilityMerkleWork](status: AvailabilityMerkleError.None,
      completed: work)

type
  MerkleTreeData = ref object ## Indexed internal hashes and private leaves permit bounded zero-hash path extraction.
    width, count: int
    flat: seq[byte]
    hashes: seq[Blake2bHash]
    root: Blake2bHash
  AvailabilityMerkleTree* = object ## No default tree can issue a completed trace.
    data: nil MerkleTreeData

proc indexedNode(flat: openArray[byte], width, first, count: int,
    budget: var HashBudget, position: int, hashes: var seq[Blake2bHash]): AvailabilityMerkleResult[NodeValue] =
  ## GP N returns a raw singleton child; only non-singleton subtrees hash the node-prefixed concatenation.
  if count == 1:
    return AvailabilityMerkleResult[NodeValue](status: AvailabilityMerkleError.None,
        completed: rawLeaf(flat, width, first))
  let leftCount = (count+1) div 2
  let left = indexedNode(flat, width, first, leftCount, budget, position+1, hashes)
  if left.error != AvailabilityMerkleError.None: return left
  let right = indexedNode(flat, width, first+leftCount, count-leftCount, budget,
      position+2*leftCount, hashes)
  if right.error != AvailabilityMerkleError.None: return right
  let a = left.value
  let b = right.value
  var preimage = default(array[NodePreimageBytes, byte])
  preimage[0] = byte('n')
  preimage[1] = byte('o')
  preimage[2] = byte('d')
  preimage[3] = byte('e')
  var used = 4
  for position in 0..<a.length:
    preimage[used] = a.bytes[position]
    inc used
  for position in 0..<b.length:
    preimage[used] = b.bytes[position]
    inc used
  let digest = hashed(preimage.toOpenArray(0, used-1), budget)
  if digest.error != AvailabilityMerkleError.None: return propagated[NodeValue, Blake2bHash](digest)
  hashes[position] = digest.value
  var completed = default(NodeValue)
  completed.length = 32
  let bytes = array[32, byte](digest.value)
  for position in 0..<32: completed.bytes[position] = bytes[position]
  AvailabilityMerkleResult[NodeValue](status: AvailabilityMerkleError.None, completed: completed)

proc prepareAvailabilityMerkleTree*(flat: openArray[byte], width, count: int,
    limits: AvailabilityMerkleLimits): AvailabilityMerkleResult[AvailabilityMerkleTree] =
  ## Charge the whole tree once before allocation; later paths do no additional primitive calls.
  let work = availabilityTreeWork(width, count)
  if work.error != AvailabilityMerkleError.None: return propagated[AvailabilityMerkleTree,
      AvailabilityMerkleWork](work)
  if flat.len != width*count: return failed[AvailabilityMerkleTree](
      AvailabilityMerkleError.InvalidInput)
  let nodes = if count == 0: 0 else: count*2-1
  if uint64(flat.len)+uint64(nodes)*32 > uint64(limits.bytes) or work.value.hashes > uint64(
      limits.hashes) or work.value.hashBytes > uint64(limits.hashBytes):
    return failed[AvailabilityMerkleTree](AvailabilityMerkleError.LimitExceeded)
  var retained = newSeq[byte](flat.len)
  for index in 0..<flat.len: retained[index] = flat[index]
  var hashes = newSeq[Blake2bHash](nodes)
  var budget = HashBudget(maximum: limits)
  var root = default(Blake2bHash)
  if count == 1:
    let digest = hashed(flat, budget)
    if digest.error != AvailabilityMerkleError.None: return propagated[AvailabilityMerkleTree,
        Blake2bHash](digest)
    root = digest.value
  elif count > 1:
    let built = indexedNode(flat, width, 0, count, budget, 0, hashes)
    if built.error != AvailabilityMerkleError.None: return propagated[AvailabilityMerkleTree,
        NodeValue](built)
    root = hashes[0]
  AvailabilityMerkleResult[AvailabilityMerkleTree](status: AvailabilityMerkleError.None,
    completed: AvailabilityMerkleTree(data: MerkleTreeData(width: width, count: count,
      flat: retained, hashes: hashes, root: root)))

proc indexedAvailabilityTrace*(tree: AvailabilityMerkleTree, index: int, leafTag: byte,
    maximum: ByteLimit): AvailabilityMerkleResult[AvailabilityTrace] =
  ## Exact root-first GP sibling nodes are copied from a private indexed tree without rehashing any subtree.
  let data = tree.data
  if data == nil: return failed[AvailabilityTrace](AvailabilityMerkleError.InvalidInput)
  let planned = shape(data.width, data.count, index, leafTag)
  if planned.error != AvailabilityMerkleError.None: return propagated[AvailabilityTrace,
      TraceShape](planned)
  if uint64(planned.value.bytes) > uint64(maximum): return failed[AvailabilityTrace](
      AvailabilityMerkleError.LimitExceeded)
  var wire = newSeq[byte](planned.value.bytes)
  var first, position = 0
  var count = data.count
  let path = planned.value
  for index in 0..<path.count:
    let step = path.steps[index]
    # Preorder positions reserve exactly 2*leftCount-1 slots for the left subtree.
    let leftCount = (count+1) div 2
    let sibling = if step.left: position+2*leftCount else: position+1
    let siblingFirst = if step.left: first+leftCount else: first
    wire[step.offset] = step.tag
    if step.tag == 0:
      for octet in 0..<32: wire[step.offset+1+octet] = array[32, byte](data.hashes[sibling])[octet]
    else:
      for octet in 0..<data.width: wire[step.offset+1+octet] = data.flat[
          siblingFirst*data.width+octet]
    if step.left:
      position += 1
      count = leftCount
    else:
      position += 2*leftCount
      first += leftCount
      count -= leftCount
  AvailabilityMerkleResult[AvailabilityTrace](status: AvailabilityMerkleError.None,
    completed: AvailabilityTrace(ready: true, root: data.root, wire: wire))
