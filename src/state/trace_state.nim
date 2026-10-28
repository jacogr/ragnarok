# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Published vector RawState wire: root, compact record count, then31-byte keys and compact blobs.
## Opaque complete maps are root-checked, never promoted to logical identities or selected-chain authority.
import ./store as state_store
import ../codec/bounded as codec_bounded
import ../codec/natural as codec_natural
import ../codec/state_trie as codec_state_trie
import ../codec/state_layout as codec_state_layout

type
  TraceStateError* {.pure.} = enum ## Refusals expose neither partial owners nor consumed-prefix coordinates.
    Uninitialized, None, InvalidOwner, Truncated, NonCanonical, LimitExceeded, DuplicateKey,
      RootMismatch, BackendFailure
  TraceStateResult*[T] = object ## Only a completed immutable owner or detached copy has a payload.
    case status: TraceStateError
    of None: completed: T
    else: discard               # Failed/default alternatives contain their reason alone.
  TraceStateData = ref object ## Private acyclic ownership preserves original record order independently of the sorted store.
    wire: seq[byte]
    snapshot: StateStoreSnapshot
  TraceState* = object ## Copying retains immutable wire and its genuinely recomputed complete-map snapshot.
    data: nil TraceStateData
  TraceStateInfo* = object ## Successful observations bind prefix extent and root to the same complete owned map.
    consumed*, entries*: int
    root*: StateRoot

func error*[T](outcome: TraceStateResult[T]): TraceStateError =
  ## Inspect the selected immutable reason without authorizing a payload.
  outcome.status
func value*[T](outcome: TraceStateResult[T]): T {.inline,
    requires: outcome.status == TraceStateError.None.} =
  ## Extract only a completely validated successful alternative.
  outcome.completed
func fail[T](reason: TraceStateError): TraceStateResult[T] =
  ## Centralize failed construction without creating a success-shaped prefix.
  TraceStateResult[T](status: reason)

proc readNatural(input: openArray[byte], maximum: int, offset: var int,
    number: var uint64): TraceStateError =
  ## The private cursor advances only over a canonical complete scalar within the caller's prefix ceiling.
  if offset >= maximum:
    return (if maximum < input.len: TraceStateError.LimitExceeded else: TraceStateError.Truncated)
  let decoded = decode(input.toOpenArray(offset, maximum-1))
  if not decoded.ok:
    if decoded.error == DecodeError.nonCanonical: return TraceStateError.NonCanonical
    return (if maximum < input.len: TraceStateError.LimitExceeded else: TraceStateError.Truncated)
  number = uint64(decoded.value)
  offset += decoded.consumed
  TraceStateError.None

proc decodeTraceState*(input: openArray[byte], limits: StateStoreLimits,
    bytes: ByteLimit): TraceStateResult[TraceState] =
  ## Borrow stable input synchronously; validate the whole consumed prefix before allocating retained records or hashing.
  let maximum = int(min(uint64(input.len), uint64(bytes)))
  if maximum < 32:
    return fail[TraceState](if maximum < input.len: TraceStateError.LimitExceeded else: TraceStateError.Truncated)
  var offset = 32
  var count = 0'u64
  let counted = readNatural(input, maximum, offset, count)
  if counted != TraceStateError.None: return fail[TraceState](counted)
  if count > uint64(limits.trie.items): return fail[TraceState](TraceStateError.LimitExceeded)
  if count > uint64((maximum-offset) div 32):
    return fail[TraceState](if maximum < input.len: TraceStateError.LimitExceeded else: TraceStateError.Truncated) # Every record needs a fixed key and at least one length byte.
  var remaining = uint64(limits.trie.totalValueBytes)
  for record in 0..<int(count):
    if maximum-offset < 31:
      return fail[TraceState](if maximum < input.len: TraceStateError.LimitExceeded else: TraceStateError.Truncated)
    offset += 31
    var size = 0'u64
    let length = readNatural(input, maximum, offset, size)
    if length != TraceStateError.None: return fail[TraceState](length)
    if size > uint64(limits.trie.perValue) or size > remaining:
      return fail[TraceState](TraceStateError.LimitExceeded) # Bound total payload before narrowing or allocating any record.
    if size > uint64(maximum-offset):
      return fail[TraceState](if maximum < input.len: TraceStateError.LimitExceeded else: TraceStateError.Truncated)
    remaining -= size
    offset += int(size)
  let consumed = offset
  var entries = newSeq[StateEntry](int(count))
  offset = 32
  var ignored = 0'u64
  discard readNatural(input, consumed, offset, ignored)
  for record in 0..<entries.len:
    var key = default(array[31, byte])
    for index in 0..<31: key[index] = input[offset+index] # The immutable first pass proved all repeated coordinates.
    offset += 31
    var size = 0'u64
    discard readNatural(input, consumed, offset, size)
    var value = newSeq[byte](int(size))
    for index in 0..<value.len: value[index] = input[
        offset+index] # Retain owned payloads, including genuinely empty values.
    offset += value.len
    entries[record] = StateEntry(key: StateKey(key), value: value)
  let made = newStateStore(entries, limits)
  if made.error != StateStoreError.None:
    let reason = case made.error
      of StateStoreError.DuplicateKey: TraceStateError.DuplicateKey # No arbitrary winner can become a complete map.
      of StateStoreError.LimitExceeded, StateStoreError.LengthOverflow: TraceStateError.LimitExceeded # Preserve trie topology and representability ceilings.
      else: TraceStateError.BackendFailure # Native primitive failures cannot produce a successful root.
    return fail[TraceState](reason)
  let snapshot = made.value.snapshot.value
  let root = array[32, byte](snapshot.commitment.root)
  for index in 0..<32:
    if root[index] != input[index]: return fail[TraceState](
        TraceStateError.RootMismatch) # Recompute the entire opaque map before accepting the asserted root.
  var wire = newSeq[byte](consumed)
  for index in 0..<consumed: wire[index] = input[index] # Retain only this prefix; a later TraceStep field is not owned by this state.
  TraceStateResult[TraceState](status: TraceStateError.None,
      completed: TraceState(data: TraceStateData(wire: wire, snapshot: snapshot)))

proc traceStateInfo*(state: TraceState): TraceStateResult[TraceStateInfo] =
  ## Return fixed observations without exposing a mutable wire array or unbound map coordinates.
  let data = state.data
  if data == nil: return fail[TraceStateInfo](TraceStateError.InvalidOwner)
  let commitment = data.snapshot.commitment
  TraceStateResult[TraceStateInfo](status: TraceStateError.None,
      completed: TraceStateInfo(consumed: data.wire.len, entries: commitment.entries,
          root: commitment.root))
proc traceStateSnapshot*(state: TraceState): TraceStateResult[StateStoreSnapshot] =
  ## Retain the exact recomputed immutable full map; this supplies no logical or chain qualification.
  let data = state.data
  if data == nil: return fail[StateStoreSnapshot](TraceStateError.InvalidOwner)
  TraceStateResult[StateStoreSnapshot](status: TraceStateError.None, completed: data.snapshot)
proc copyTraceState*(state: TraceState, bytes: ByteLimit): TraceStateResult[seq[byte]] =
  ## Copy the original validated prefix in original record order; the caller may freely mutate its detached output.
  let data = state.data
  if data == nil: return fail[seq[byte]](TraceStateError.InvalidOwner)
  if uint64(data.wire.len) > uint64(bytes): return fail[seq[byte]](TraceStateError.LimitExceeded)
  var output = newSeq[byte](data.wire.len)
  for index in 0..<output.len: output[index] = data.wire[
      index] # No caller alias into immutable retained bytes escapes.
  TraceStateResult[seq[byte]](status: TraceStateError.None, completed: output)

proc encodeTraceState*(snapshot: StateStoreSnapshot, bytes: ByteLimit): TraceStateResult[seq[byte]] =
  ## Encode a complete initialized store in deterministic key order using the single published compact wire representation.
  if snapshot.forkStateStore.error != StateStoreError.None: return fail[seq[byte]](
      TraceStateError.InvalidOwner)
  let commitment = snapshot.commitment
  let count = encode(JamNatural(uint64(commitment.entries)))
  let maximum = min(uint64(bytes), uint64(high(int)))
  var extent = 32'u64+uint64(count.len)
  if extent > maximum: return fail[seq[byte]](TraceStateError.LimitExceeded)
  for index in 0..<commitment.entries:
    let key = snapshot.keyAt(StateEntryIndex(index)).value
    let size = uint64(snapshot.lookup(key).value.byteLength)
    let encoded = encode(JamNatural(size))
    let fixed = 31'u64+uint64(encoded.len)
    if fixed > maximum-extent: return fail[seq[byte]](TraceStateError.LimitExceeded)
    extent += fixed
    if size > maximum-extent: return fail[seq[byte]](TraceStateError.LimitExceeded)
    extent += size # Subtraction proves every sum under wrapping arithmetic before output allocation.
  var output = newSeq[byte](int(extent))
  let root = array[32, byte](commitment.root)
  for index in 0..<32: output[index] = root[index] # Preserve the complete store's already verified commitment.
  var offset = 32
  for index in 0..<count.len:
    output[offset] = count.bytes[index]
    inc offset # Exact scalar width was included in preflight.
  for index in 0..<commitment.entries:
    let key = snapshot.keyAt(StateEntryIndex(index)).value
    for octet in array[31, byte](key):
      output[offset] = octet
      inc offset # Each fixed key extent was admitted before allocation.
    let value = snapshot.lookup(key).value.bytes
    let encoded = encode(JamNatural(uint64(value.len)))
    for scalar in 0..<encoded.len:
      output[offset] = encoded.bytes[scalar]
      inc offset # Only the canonical natural's occupied bytes belong to the wire.
    for octet in value:
      output[offset] = octet
      inc offset # Empty values contribute a zero length and no fabricated payload.
  TraceStateResult[seq[byte]](status: TraceStateError.None, completed: output)
