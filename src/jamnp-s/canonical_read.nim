# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Complete canonical CE128/129/136/143 read backends. Run outside native callbacks under a host read
## lease; only frozen bounded wire replies survive publication. No light-state map is accepted.
import std/assertions
import ./[read_stream, block_service, preimage_announcement]
import ../chain/[genesis, provider, reports]
import ../codec/[bounded, natural]
import ../codec/state/[layout, service_values]
import ../state/[store, snapshot_proof, trie_proof]
import ../crypto/primitives

const BoundaryBudget = 512*64 ## Two at-most256-node paths cover the 248-bit serialized-key space.
func compare(left, right: StateKey): int =
  ## Compare exact 31-byte serialized keys, independent of host endian or signed char ordering.
  let a = array[31, byte](left)
  let b = array[31, byte](right)
  for index in 0..<31:
    if a[index] < b[index]: return -1
    if a[index] > b[index]: return 1
  0
func hashAt(payload: openArray[byte]): BlockHash {.requires: payload.len >= 32.} =
  ## Fixed hash bytes are copied only after request framing has proved the extent.
  var raw = default(array[32, byte])
  for index in 0..<32: raw[index] = payload[index]
  BlockHash(raw)
proc appendFrame(output: var seq[byte], payload: seq[byte]) =
  ## Callers preflight the aggregate ceiling; each message has one E4 and no count prefix.
  assert payload.len <= MaxReadReplyBytes-4 and output.len <= MaxReadReplyBytes-payload.len-4
  for index in 0..<4: output.add(byte((uint32(payload.len) shr (8*index)) and 255))
  for octet in payload: output.add(octet)
proc stateReply(view: ChainView, request: ReadRequest): ReadResult[ReadReply] =
  ## Select a contiguous sorted range first, then build both boundary witnesses in one map pass.
  let payload = request.payload
  let found = view.blockAt(hashAt(payload))
  if found.error != GenesisError.None: return readFailure[ReadReply](ReadError.Unavailable)
  let snapshot = found.value
  if snapshot.keyCount > 16384: return readFailure[ReadReply](
      ReadError.LimitExceeded) # Bound index traversal before proof preflight.
  var start, finish = default(array[31, byte])
  var maximum = 0'u32
  for index in 0..<31:
    start[index] = payload[32+index]
    finish[index] = payload[63+index]
  for index in 0..<4: maximum = maximum or (uint32(payload[94+index]) shl (8*index))
  let first = StateKey(start)
  let endKey = StateKey(finish)
  if compare(first, endKey) > 0: return readFailure[ReadReply](ReadError.InvalidRequest)
  var pairs: seq[byte] = @[]
  var last = first
  var count = 0
  let budget = min(uint64(maximum), uint64(MaxReadReplyBytes))
  for index in 0..<snapshot.keyCount:
    let key = snapshot.keyAt(StateKeyIndex(index))
    if compare(key, first) < 0: continue # Earlier keys cannot enter the inclusive range.
    if compare(key, endKey) > 0: break # The private snapshot index is already sorted.
    let value = snapshot.lookup(key)
    if value.error != StateStoreError.None: return readFailure[ReadReply](ReadError.BackendFailure)
    let length = value.value.byteLength
    if length > 4*1024*1024: return readFailure[ReadReply](ReadError.LimitExceeded)
    let natural = encode(JamNatural(uint64(length)))
    let extent = 31+natural.len+length # The explicit per-value ceiling proves host arithmetic.
    let needed = uint64(pairs.len)+uint64(extent)+uint64(BoundaryBudget+8)
    if needed > uint64(MaxReadReplyBytes):
      if count == 0: return readFailure[ReadReply](ReadError.LimitExceeded)
      break # A local resource ceiling is independent of the protocol's single-pair exception.
    if count > 0 and needed > budget: break # Conservative boundary reservation permits bounded underfilling.
    let raw = array[31, byte](key)
    for octet in raw: pairs.add(octet)
    for offset in 0..<natural.len: pairs.add(natural.bytes[offset])
    for octet in value.value.bytes: pairs.add(octet) # Size was inspected before this detached copy.
    last = key
    inc count
  var queries = @[first]
  if count > 0: queries.add(last) # Empty ranges have no last included pair; retain only the start path.
  let proofLimits = StateProofLimits(nodes: ElementLimit(256), valueBytes: ByteLimit(4*1024*1024))
  let proofs = generateStateProofs(snapshot.stateSnapshot, queries, genesisStoreLimits().trie,
    proofLimits, StateProofBatchLimits(items: ElementLimit(2), nodes: ElementLimit(512),
      valueBytes: ByteLimit(8*1024*1024)))
  if proofs.error != StateProofError.None:
    return readFailure[ReadReply](ReadError.BackendFailure) # No partial map/proof becomes a successful range.
  var nodes: seq[EncodedStateNode] = @[]
  for index in 0..<proofs.value.len:
    let path = proofs.value.queryAt(index)
    if path.error != StateProofError.None: return readFailure[ReadReply](ReadError.BackendFailure)
    for offset in 0..<path.value.proof.len:
      let node = path.value.proof.nodeAt(offset)
      if node.error != StateProofError.None: return readFailure[ReadReply](ReadError.BackendFailure)
      var duplicate = false
      for prior in nodes:
        if array[64, byte](prior) == array[64, byte](node.value): duplicate = true
      if not duplicate: nodes.add(node.value) # Root-first path union preserves every parent-before-child relation.
  var boundaries: seq[byte] = @[]
  for node in nodes:
    for octet in array[64, byte](node): boundaries.add(octet)
  let size = boundaries.len+pairs.len+8 # Both independently bounded owners fit the hard local ceiling.
  if uint64(size) > budget and count != 1: return readFailure[ReadReply](ReadError.LimitExceeded)
  var wire: seq[byte] = @[]
  appendFrame(wire, boundaries)
  appendFrame(wire, pairs)
  captureReadReply(request, wire)
proc preimageReply(view: ChainView, request: ReadRequest): ReadResult[ReadReply] =
  ## Resolve from canonical service preimages, never the CE136 report DB or a development bank.
  let source = view.bestBlock
  if source.error != GenesisError.None: return readFailure[ReadReply](ReadError.Unavailable)
  let snapshot = source.value
  if snapshot.serviceCount > 16384: return readFailure[ReadReply](
      ReadError.LimitExceeded) # Bound candidate hashing even for a wider host store.
  let expected = array[32, byte](hashAt(request.payload))
  var remainingHashBytes = 32*1024*1024
  for index in 0..<snapshot.serviceCount:
    let key = servicePreimageKey(snapshot.serviceAt(ServiceListIndex(index)),
      ServicePreimageHash(expected), ByteLimit(32))
    if key.error != ServiceValueError.None: return readFailure[ReadReply](ReadError.BackendFailure)
    let found = snapshot.lookup(key.value)
    if found.error == StateStoreError.MissingKey: continue # This service has no matching canonical preimage.
    if found.error != StateStoreError.None: return readFailure[ReadReply](ReadError.BackendFailure)
    if found.value.byteLength > MaxReadReplyBytes-4: return readFailure[ReadReply](
        ReadError.LimitExceeded)
    if found.value.byteLength > remainingHashBytes: return readFailure[ReadReply](
        ReadError.LimitExceeded)
    remainingHashBytes -= found.value.byteLength
    let bytes = found.value.bytes
    let hashed = blake2b256(bytes)
    if hashed.error != CryptoError.None: return readFailure[ReadReply](ReadError.BackendFailure)
    if array[32, byte](hashed.value) != expected: continue # Truncated storage-key collisions cannot substitute another blob.
    var wire: seq[byte] = @[]
    appendFrame(wire, bytes)
    return captureReadReply(request, wire)
  readFailure[ReadReply](ReadError.Unavailable)
proc announcementReply(view: ChainView, request: ReadRequest): ReadResult[ReadReply] =
  ## Validate canonical outstanding request state before planning a same-connection fetch; acknowledgment has no E4 body.
  let decoded = decodeAnnouncement(request.payload)
  if decoded.error != ReadError.None: return readFailure[ReadReply](decoded.error)
  let requested = view.requested(decoded.value)
  if requested != ReadError.None: return readFailure[ReadReply](requested)
  let lookup = decodeReadRequest(ReadKind.Preimage, array[32, byte](decoded.value.hash))
  if lookup.error != ReadError.None: return readFailure[ReadReply](ReadError.InvalidRequest)
  let held = preimageReply(view, lookup.value)
  case held.error
  of ReadError.None: captureReadReply(request, []) # Canonical possession suppresses a redundant remote fetch.
  of ReadError.Unavailable: captureReadReply(request, [], ReadEffect.FetchPreimage)
  else: readFailure[ReadReply](held.error) # Integrity/resource failures never masquerade as missing local content.
proc reportReply(view: ChainView, request: ReadRequest): ReadResult[ReadReply] =
  ## Reuse bounded selected-head C10/C14 retention; no report archive or peer-provided state authority is inferred.
  if view.fuzzOnly: return readFailure[ReadReply](ReadError.InvalidRequest)
  let payload = request.payload
  var identity = default(array[32, byte])
  for index in 0..<32: identity[index] = payload[index]
  let found = view.reportAt(WorkReportHash(identity), ByteLimit(MaxReadReplyBytes-4))
  case found.error
  of ReportReadError.None:
    let metadata = ownedReportInfo(found.value)
    if metadata.error != OwnershipError.None: return readFailure[ReadReply](
        ReadError.BackendFailure)
    if metadata.value.consumed > MaxReadReplyBytes-4: return readFailure[ReadReply](
        ReadError.LimitExceeded)
    var body = newSeq[byte](metadata.value.consumed)
    let encoded = encodeOwnedReport(found.value, body)
    if encoded.error != OwnershipError.None or encoded.value != body.len:
      return readFailure[ReadReply](ReadError.BackendFailure)
    var wire: seq[byte] = @[]
    appendFrame(wire, body) # CE136 carries the bare report, excluding guarantee slot, credentials and any sequence count.
    captureReadReply(request, wire)
  of ReportReadError.Missing, ReportReadError.Uninitialized:
    readFailure[ReadReply](ReadError.Unavailable) # Missing content resets the exact requesting stream.
  of ReportReadError.LimitExceeded: readFailure[ReadReply](ReadError.LimitExceeded)
  of ReportReadError.Malformed, ReportReadError.BackendFailure:
    readFailure[ReadReply](ReadError.BackendFailure) # Malformed authoritative state cannot be hidden as an ordinary miss.
proc serveCanonicalRead*(view: ChainView, request: ReadRequest): ReadResult[ReadReply] =
  ## One full-view host entry point returns only frozen transport bytes, never a retained graph.
  if not request.valid: return readFailure[ReadReply](ReadError.InvalidRequest)
  case request.kind
  of ReadKind.Guarantee, ReadKind.Assurance, ReadKind.TicketProxy, ReadKind.TicketDistribution,
      ReadKind.Availability, ReadKind.Audit, ReadKind.Bundle, ReadKind.SegmentShards,
          ReadKind.ProvenSegmentShards, ReadKind.Segments:
    readFailure[ReadReply](ReadError.InvalidRequest) # These methods require typed upload or original availability admission, never a generic canonical response.
  of ReadKind.PreimageAnnouncement: announcementReply(view, request)
  of ReadKind.Report: reportReply(view, request)
  of ReadKind.State: stateReply(view, request)
  of ReadKind.Preimage: preimageReply(view, request)
  of ReadKind.Blocks:
    let query = decodeBlockQuery(request.payload)
    if query.error != BlockServiceError.None: return readFailure[ReadReply](
        ReadError.InvalidRequest)
    let reply = serveBlocks(view, query.value)
    case reply.error
    of BlockServiceError.None: captureReadReply(request, reply.value.bytes)
    of BlockServiceError.LimitExceeded: readFailure[ReadReply](ReadError.LimitExceeded)
    else: readFailure[ReadReply](ReadError.Unavailable) # Canonical absence/reset semantics remain shared.
