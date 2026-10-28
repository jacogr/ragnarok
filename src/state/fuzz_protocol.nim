# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Pinned JAM fuzzer-v1 messages own bounded immutable wire and structurally validated children.
## Wire capture proves neither protocol negotiation nor genesis trust, STF success or logical completeness.
import std/assertions
import ./store as state_store
import ./trace_state as state_trace_state
import ../codec/bounded as codec_bounded
import ../codec/natural as codec_natural
import ../codec/header as codec_header
import ../codec/block_codec as codec_block_codec
import ../codec/state_layout as codec_state_layout
import ../codec/state_trie as codec_state_trie
import ../lib/utf8 as lib_utf8

type
  FuzzKind* {.pure.} = enum ## Published one-byte discriminants have no alternate representation.
    PeerInfo = 0, Initialize = 1, StateRoot = 2, ImportBlock = 3, GetState = 4, State = 5, Error = 255
  FuzzError* {.pure.} = enum ## Failed/default results retain no owner or consumed-prefix coordinates.
    Uninitialized, None, InvalidOwner, WrongKind, Truncated, NonCanonical, LimitExceeded,
    InvalidTag, InvalidText, HeaderFailure, BlockFailure, DuplicateKey, StateFailure, TrailingBytes
  FuzzResult*[T] = object ## Only the private completed alternative can expose a validated value.
    case status: FuzzError
    of None: completed: T
    else: discard         # Every failure is reason-only.
  FuzzVersion* = object ## Exact three E1 protocol version components remain distinct from a text label.
    major*, minor*, patch*: byte
  FuzzPeer* = object ## Copied application identity and feature declarations authorize no session by themselves.
    protocol*: byte
    features*: uint32
    jam*, app*: FuzzVersion
    name*: string
  FuzzHeaderHash* = distinct array[32, byte] ## A requested/imported header identity is not a state root.
  FuzzAncestor* = object ## Ancestry has the pinned E4 slot and fixed header-hash width.
    slot*: HeaderSlot
    hash*: FuzzHeaderHash
  FuzzLimits* = object ## All limits are trusted caller policy, independent of untrusted framing/count fields.
    bytes*, text*: ByteLimit
    state*: StateStoreLimits
    frame*: FrameConfig
  FuzzInfo* = object ## Kind and exact message extent belong to the same initialized immutable owner.
    kind*: FuzzKind
    bytes*: int
  FuzzData = ref object ## Private acyclic storage retains only complete wire and independently owned children.
    kind: FuzzKind
    wire: seq[byte]
    peer: FuzzPeer
    header: OwnedHeader
    state: StateStoreSnapshot
    ancestors: seq[FuzzAncestor]
    body: OwnedBlock
    hash: array[32, byte]
    text: string
  FuzzMessage* = object ## Default ownership is invalid; copying shares immutable storage only.
    data: nil FuzzData

func error*[T](outcome: FuzzResult[T]): FuzzError =
  ## Inspect an immutable reason without selecting a successful payload.
  outcome.status
func value*[T](outcome: FuzzResult[T]): T {.inline, requires: outcome.status == FuzzError.None.} =
  ## Extract only the complete selected alternative.
  outcome.completed
func fail[T](reason: FuzzError): FuzzResult[T] =
  ## Centralize failure without constructing a success-shaped prefix.
  FuzzResult[T](status: reason)
proc copied(input: openArray[byte]): seq[byte] =
  ## Detach bytes before any caller storage can mutate or retire.
  result = newSeq[byte](input.len)
  for index in 0..<input.len: result[index] = input[index]
proc readNatural(input: openArray[byte], cursor: var int, number: var uint64): FuzzError =
  ## Advance a private cursor only over one complete canonical natural.
  if cursor >= input.len: return FuzzError.Truncated
  let decoded = decode(input.toOpenArray(cursor, input.high))
  if not decoded.ok:
    return (if decoded.error == DecodeError.nonCanonical: FuzzError.NonCanonical else: FuzzError.Truncated)
  number = uint64(decoded.value)
  cursor += decoded.consumed
  FuzzError.None
proc readText(input: openArray[byte], cursor: var int, maximum: ByteLimit,
    text: var string): FuzzError =
  ## Validate complete extent and Unicode scalars before retaining any text.
  var size = 0'u64
  let reason = readNatural(input, cursor, size)
  if reason != FuzzError.None: return reason
  if size > uint64(maximum): return FuzzError.LimitExceeded
  if size > uint64(input.len-cursor): return FuzzError.Truncated
  var owned = newString(int(size))
  for index in 0..<owned.len: owned[index] = char(input[cursor+index])
  if not validUtf8(owned): return FuzzError.InvalidText
  cursor += owned.len
  text = owned
  FuzzError.None
proc readState(input: openArray[byte], cursor: var int,
    limits: StateStoreLimits): FuzzResult[StateStoreSnapshot] =
  ## The protocol State has no advertised root; scan all compact records before allocation and compute the complete opaque root.
  var count = 0'u64
  let reason = readNatural(input, cursor, count)
  if reason != FuzzError.None: return fail[StateStoreSnapshot](reason)
  if count > uint64(limits.trie.items): return fail[StateStoreSnapshot](FuzzError.LimitExceeded)
  if count > uint64((input.len-cursor) div 32): return fail[StateStoreSnapshot](FuzzError.Truncated)
  let start = cursor
  var available = uint64(limits.trie.totalValueBytes)
  for record in 0..<int(count):
    if input.len-cursor < 31: return fail[StateStoreSnapshot](FuzzError.Truncated)
    cursor += 31
    var size = 0'u64
    let length = readNatural(input, cursor, size)
    if length != FuzzError.None: return fail[StateStoreSnapshot](length)
    if size > uint64(limits.trie.perValue) or size > available:
      return fail[StateStoreSnapshot](FuzzError.LimitExceeded)
    if size > uint64(input.len-cursor): return fail[StateStoreSnapshot](FuzzError.Truncated)
    available -= size
    cursor += int(size) # All conversions and additions fit the admitted complete input extent.
  let stop = cursor
  cursor = start
  var entries = newSeq[StateEntry](int(count))
  for record in 0..<entries.len:
    var key = default(array[31, byte])
    for index in 0..<31: key[index] = input[cursor+index]
    cursor += 31
    var size = 0'u64
    discard readNatural(input, cursor, size) # Immutable input and the first pass prove every repeated field.
    var bytes = newSeq[byte](int(size))
    for index in 0..<bytes.len: bytes[index] = input[cursor+index]
    cursor += bytes.len
    entries[record] = StateEntry(key: StateKey(key), value: bytes)
  assert cursor == stop
  let store = newStateStore(entries, limits)
  if store.error != StateStoreError.None:
    let mapped = case store.error
      of StateStoreError.DuplicateKey: FuzzError.DuplicateKey # No arbitrary duplicate winner forms a complete map.
      of StateStoreError.LimitExceeded, StateStoreError.LengthOverflow: FuzzError.LimitExceeded
      else: FuzzError.StateFailure # Primitive/backend failures are not malformed input successes.
    return fail[StateStoreSnapshot](mapped)
  FuzzResult[StateStoreSnapshot](status: FuzzError.None, completed: store.value.snapshot.value)

proc decodeFuzzMessage*(input: openArray[byte], limits: FuzzLimits): FuzzResult[FuzzMessage] =
  ## Decode exactly one complete unframed message; no trailer or failed child grants an owner.
  if uint64(input.len) > uint64(limits.bytes): return fail[FuzzMessage](FuzzError.LimitExceeded)
  if input.len == 0: return fail[FuzzMessage](FuzzError.Truncated)
  var data = FuzzData()
  var cursor = 1
  case input[0]
  of 0:
    if input.len-cursor < 11: return fail[FuzzMessage](FuzzError.Truncated)
    data.kind = FuzzKind.PeerInfo
    data.peer.protocol = input[cursor]
    inc cursor
    for index in 0..<4: data.peer.features = data.peer.features or (uint32(input[
        cursor+index]) shl (8*index))
    cursor += 4
    data.peer.jam = FuzzVersion(major: input[cursor], minor: input[cursor+1], patch: input[cursor+2])
    cursor += 3
    data.peer.app = FuzzVersion(major: input[cursor], minor: input[cursor+1], patch: input[cursor+2])
    cursor += 3
    let reason = readText(input, cursor, limits.text, data.peer.name)
    if reason != FuzzError.None: return fail[FuzzMessage](
        reason) # Versions and feature intersection belong to session negotiation.
  of 1:
    data.kind = FuzzKind.Initialize
    if cursor == input.len: return fail[FuzzMessage](FuzzError.HeaderFailure)
    let frame = limits.frame
    let policy = HeaderConfig(cores: frame.cores, authorValidators: frame.validators,
        epochSlots: frame.epochSlots, maxBytes: ByteLimit(min(uint64(frame.maxBytes), uint64(
            input.len-cursor))))
    let head = decodeHeader(input.toOpenArray(cursor, input.high), policy)
    if head.error != HeaderError.None: return fail[FuzzMessage](FuzzError.HeaderFailure)
    data.header = head.value.owner
    cursor += head.value.consumed
    let state = readState(input, cursor, limits.state)
    if state.error != FuzzError.None: return fail[FuzzMessage](state.error)
    data.state = state.value
    var count = 0'u64
    let reason = readNatural(input, cursor, count)
    if reason != FuzzError.None: return fail[FuzzMessage](reason)
    if count > 24: return fail[FuzzMessage](FuzzError.LimitExceeded)
    if count > uint64((input.len-cursor) div 36): return fail[FuzzMessage](FuzzError.Truncated)
    data.ancestors = newSeq[FuzzAncestor](int(count))
    for record in 0..<data.ancestors.len:
      var slot = 0'u32
      for index in 0..<4: slot = slot or (uint32(input[cursor+index]) shl (8*index))
      cursor += 4
      var hash = default(array[32, byte])
      for index in 0..<32: hash[index] = input[cursor+index]
      cursor += 32
      data.ancestors[record] = FuzzAncestor(slot: HeaderSlot(slot), hash: FuzzHeaderHash(hash))
  of 2, 4:
    data.kind = if input[0] == 2: FuzzKind.StateRoot else: FuzzKind.GetState
    if input.len-cursor < 32: return fail[FuzzMessage](FuzzError.Truncated)
    for index in 0..<32: data.hash[index] = input[cursor+index]
    cursor += 32 # StateRoot and GetState remain distinct message kinds despite equal wire widths.
  of 3:
    data.kind = FuzzKind.ImportBlock
    if cursor == input.len: return fail[FuzzMessage](FuzzError.BlockFailure)
    var policy = limits.frame
    policy.maxBytes = ByteLimit(min(uint64(policy.maxBytes), uint64(input.len-cursor)))
    let decodedBlock = decodeBlock(input.toOpenArray(cursor, input.high), policy)
    if decodedBlock.error != FrameError.None: return fail[FuzzMessage](FuzzError.BlockFailure)
    data.body = decodedBlock.value.owner
    cursor += decodedBlock.value.consumed
  of 5:
    data.kind = FuzzKind.State
    let state = readState(input, cursor, limits.state)
    if state.error != FuzzError.None: return fail[FuzzMessage](state.error)
    data.state = state.value # A computed opaque root supplies no chain or logical identity qualification.
  of 255:
    data.kind = FuzzKind.Error
    let reason = readText(input, cursor, limits.text, data.text)
    if reason != FuzzError.None: return fail[FuzzMessage](reason)
  else:
    return fail[FuzzMessage](FuzzError.InvalidTag) # Unknown discriminants cannot select an initialized default child.
  if cursor != input.len: return fail[FuzzMessage](FuzzError.TrailingBytes)
  data.wire = copied(input)
  FuzzResult[FuzzMessage](status: FuzzError.None, completed: FuzzMessage(data: data))

proc fuzzInfo*(source: FuzzMessage): FuzzResult[FuzzInfo] =
  ## Observe only an initialized message's own kind and exact extent.
  let data = source.data
  if data == nil: return fail[FuzzInfo](FuzzError.InvalidOwner)
  FuzzResult[FuzzInfo](status: FuzzError.None, completed: FuzzInfo(kind: data.kind,
      bytes: data.wire.len))
proc fuzzPeer*(source: FuzzMessage): FuzzResult[FuzzPeer] =
  ## Return a copied peer declaration only for a successful PeerInfo owner.
  let data = source.data
  if data == nil: return fail[FuzzPeer](FuzzError.InvalidOwner)
  if data.kind != FuzzKind.PeerInfo: return fail[FuzzPeer](FuzzError.WrongKind)
  FuzzResult[FuzzPeer](status: FuzzError.None, completed: data.peer)
proc fuzzHeader*(source: FuzzMessage): FuzzResult[OwnedHeader] =
  ## Retain an independent immutable header child, never a fabricated default header.
  let data = source.data
  if data == nil: return fail[OwnedHeader](FuzzError.InvalidOwner)
  if data.kind != FuzzKind.Initialize: return fail[OwnedHeader](FuzzError.WrongKind)
  FuzzResult[OwnedHeader](status: FuzzError.None, completed: data.header)
proc fuzzBlock*(source: FuzzMessage): FuzzResult[OwnedBlock] =
  ## Retain the captured original block without granting admission or installation authority.
  let data = source.data
  if data == nil: return fail[OwnedBlock](FuzzError.InvalidOwner)
  if data.kind != FuzzKind.ImportBlock: return fail[OwnedBlock](FuzzError.WrongKind)
  FuzzResult[OwnedBlock](status: FuzzError.None, completed: data.body)
proc fuzzState*(source: FuzzMessage): FuzzResult[StateStoreSnapshot] =
  ## Retain the complete independently rooted map for State or Initialize only.
  let data = source.data
  if data == nil: return fail[StateStoreSnapshot](FuzzError.InvalidOwner)
  if data.kind notin {FuzzKind.Initialize, FuzzKind.State}: return fail[StateStoreSnapshot](
      FuzzError.WrongKind)
  FuzzResult[StateStoreSnapshot](status: FuzzError.None, completed: data.state)
proc fuzzAncestors*(source: FuzzMessage): FuzzResult[seq[FuzzAncestor]] =
  ## Copy the complete bounded ancestry list; no mutable alias into the message escapes.
  let data = source.data
  if data == nil: return fail[seq[FuzzAncestor]](FuzzError.InvalidOwner)
  if data.kind != FuzzKind.Initialize: return fail[seq[FuzzAncestor]](FuzzError.WrongKind)
  var output = newSeq[FuzzAncestor](data.ancestors.len)
  for index in 0..<output.len: output[index] = data.ancestors[index]
  FuzzResult[seq[FuzzAncestor]](status: FuzzError.None, completed: output)
proc fuzzRoot*(source: FuzzMessage): FuzzResult[codec_state_trie.StateRoot] =
  ## A StateRoot response is not interchangeable with a GetState header identity.
  let data = source.data
  if data == nil: return fail[codec_state_trie.StateRoot](FuzzError.InvalidOwner)
  if data.kind != FuzzKind.StateRoot: return fail[codec_state_trie.StateRoot](FuzzError.WrongKind)
  FuzzResult[codec_state_trie.StateRoot](status: FuzzError.None,
      completed: codec_state_trie.StateRoot(data.hash))
proc fuzzRequestedHeader*(source: FuzzMessage): FuzzResult[FuzzHeaderHash] =
  ## Extract a complete fixed request identity only from GetState.
  let data = source.data
  if data == nil: return fail[FuzzHeaderHash](FuzzError.InvalidOwner)
  if data.kind != FuzzKind.GetState: return fail[FuzzHeaderHash](FuzzError.WrongKind)
  FuzzResult[FuzzHeaderHash](status: FuzzError.None, completed: FuzzHeaderHash(data.hash))
proc fuzzText*(source: FuzzMessage): FuzzResult[string] =
  ## Return validated error text without treating out-of-protocol internal faults as consensus errors.
  let data = source.data
  if data == nil: return fail[string](FuzzError.InvalidOwner)
  if data.kind != FuzzKind.Error: return fail[string](FuzzError.WrongKind)
  FuzzResult[string](status: FuzzError.None, completed: data.text)
proc copyFuzzMessage*(source: FuzzMessage, maximum: ByteLimit): FuzzResult[seq[byte]] =
  ## Copy original exact unframed wire, including upstream State record order.
  let data = source.data
  if data == nil: return fail[seq[byte]](FuzzError.InvalidOwner)
  if uint64(data.wire.len) > uint64(maximum): return fail[seq[byte]](FuzzError.LimitExceeded)
  FuzzResult[seq[byte]](status: FuzzError.None, completed: copied(data.wire))


proc addNatural(output: var seq[byte], value: uint64) =
  ## Append a canonical bounded natural supplied by already validated local sizes.
  let encoded = encode(JamNatural(value))
  for index in 0..<encoded.len: output.add(encoded.bytes[index])
proc newFuzzPeer*(peer: FuzzPeer, limits: FuzzLimits): FuzzResult[FuzzMessage] =
  ## Encode one bounded UTF-8 declaration; session negotiation remains a separate caller decision.
  let prefix = encode(JamNatural(uint64(peer.name.len)))
  let fixed = 12+prefix.len
  let maximum = min(uint64(limits.bytes), uint64(high(int)))
  if uint64(peer.name.len) > uint64(limits.text) or maximum < uint64(fixed) or
      uint64(peer.name.len) > maximum-uint64(fixed):
    return fail[FuzzMessage](FuzzError.LimitExceeded)
  var wire = @[0'u8, peer.protocol]
  for index in 0..<4: wire.add(byte((peer.features shr (8*index)) and 255))
  for version in [peer.jam, peer.app]:
    for octet in [version.major, version.minor, version.patch]: wire.add(octet)
  wire.addNatural(uint64(peer.name.len))
  for character in peer.name: wire.add(byte(character))
  decodeFuzzMessage(wire, limits)
proc newFuzzRoot*(root: codec_state_trie.StateRoot, limits: FuzzLimits): FuzzResult[FuzzMessage] =
  ## Construct only a complete native root response under the same explicit message cap.
  if uint64(limits.bytes) < 33: return fail[FuzzMessage](FuzzError.LimitExceeded)
  var wire = @[2'u8]
  for octet in array[32, byte](root): wire.add(octet)
  decodeFuzzMessage(wire, limits)
proc newFuzzError*(text: string, limits: FuzzLimits): FuzzResult[FuzzMessage] =
  ## Encode bounded protocol error text; callers must reserve this response for consensus import failures.
  let prefix = encode(JamNatural(uint64(text.len)))
  let fixed = 1+prefix.len
  let maximum = min(uint64(limits.bytes), uint64(high(int)))
  if uint64(text.len) > uint64(limits.text) or maximum < uint64(fixed) or
      uint64(text.len) > maximum-uint64(fixed):
    return fail[FuzzMessage](FuzzError.LimitExceeded)
  var wire = @[255'u8]
  wire.addNatural(uint64(text.len))
  for character in text: wire.add(byte(character))
  decodeFuzzMessage(wire, limits)
proc newFuzzState*(snapshot: StateStoreSnapshot, limits: FuzzLimits): FuzzResult[FuzzMessage] =
  ## Strip only RawState's independently computed root; protocol State retains compact count/key/value framing.
  let maximum = min(uint64(limits.bytes), uint64(high(int)-32))
  if maximum == 0: return fail[FuzzMessage](FuzzError.LimitExceeded)
  let encoded = encodeTraceState(snapshot, ByteLimit(maximum+31))
  if encoded.error != TraceStateError.None:
    let mapped = case encoded.error
      of TraceStateError.LimitExceeded: FuzzError.LimitExceeded
      of TraceStateError.InvalidOwner: FuzzError.InvalidOwner
      else: FuzzError.StateFailure # Preserve output/owner refusal independently from backend failures.
    return fail[FuzzMessage](mapped)
  let original = encoded.value
  var wire = @[5'u8]
  for index in 32..<original.len: wire.add(original[index])
  decodeFuzzMessage(wire, limits)

proc fuzzFrameLength*(prefix: openArray[byte], maximum: ByteLimit): FuzzResult[int] =
  ## Validate the exact E4 transport length before any socket payload allocation.
  if prefix.len < 4: return fail[int](FuzzError.Truncated)
  if prefix.len != 4: return fail[int](FuzzError.TrailingBytes)
  var length = 0'u64
  for index in 0..<4: length = length or (uint64(prefix[index]) shl (8*index))
  if length == 0: return fail[int](FuzzError.Truncated)
  if length > uint64(maximum) or length > uint64(high(int)-4): return fail[int](
      FuzzError.LimitExceeded)
  FuzzResult[int](status: FuzzError.None, completed: int(length))
proc encodeFuzzFrame*(source: FuzzMessage, maximum: ByteLimit): FuzzResult[seq[byte]] =
  ## Prefix exactly one complete message with E4 payload size; no partial frame is published.
  let data = source.data
  if data == nil: return fail[seq[byte]](FuzzError.InvalidOwner)
  let length = data.wire.len
  if uint64(length) > uint64(maximum) or uint64(length) > uint64(high(uint32)) or length > high(int)-4:
    return fail[seq[byte]](FuzzError.LimitExceeded)
  var output = newSeq[byte](length+4)
  for index in 0..<4: output[index] = byte((uint64(length) shr (8*index)) and 255)
  for index in 0..<length: output[index+4] = data.wire[index]
  FuzzResult[seq[byte]](status: FuzzError.None, completed: output)
