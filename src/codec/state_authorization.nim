# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## GP 0.8.0 T(state) chapters 1/2 and authorization eq:authstatecomposition. Entries encode
## ordered core pools/queues; no authorization or state transition is executed.
##
## Exposes authorization profiles and snapshots, state entry construction/decoding and bounded
## per-core authorizer access.

import std/assertions
import ./natural as codec_natural
import ./bounded as codec_bounded
import ./assurances as codec_assurances
import ./state_layout as codec_state_layout
import ./state_trie as codec_state_trie
from ./work_report as codec_work_report import AuthorizerHash
export AuthorizerHash

type
  AuthorizationKind* {.pure.} = enum ## Distinguishes variable pools (chapter 1) from fixed queues (chapter 2).
    Pools, Queues
  AuthorizerRow* = seq[AuthorizerHash] ## Synchronous borrowed source row; neither its backing storage nor any mutable alias is retained.
  AuthorizationCoreIndex* = distinct uint64 ## An ordinal in the configured core sequence, distinct from an authorizer position.
  AuthorizationIndex* = distinct uint64 ## A position within one core's ordered pool or queue.
  AuthorizationConfig* = object ## Explicit chain cardinality and caller ceilings for total hashes and complete payload bytes.
    cores*: CoreCount
    maxHashes*: ElementLimit
    maxBytes*: ByteLimit
  AuthorizationError* {.pure.} = enum ## Failed/default results have no entry, owner, count or consumed cursor.
    Uninitialized, None, InvalidConfig, InvalidCount, Truncated, NonCanonical,
    LimitExceeded, LengthOverflow, InvalidOwner, InvalidIndex, InvalidTag
  AuthorizationResult*[T] = object ## Only success exposes the complete selected application value.
    case status: AuthorizationError
    of None:
      completed: T                 # Complete success alone carries application data.
    else:
      discard                      # No default value or partial progress on failure.
  ## Private acyclic ARC storage binds ordered copied hashes to their validated component kind.
  AuthorizationData = ref object
    kind: AuthorizationKind
    rows: seq[AuthorizerRow]
  AuthorizationSnapshot* = object ## Value handle shares immutable private storage; replacing a handle cannot mutate other copies.
    data: nil AuthorizationData
  AuthorizationRead* = object ## Complete prefix decoding carries its immutable snapshot and exact consumed byte extent.
    snapshot*: AuthorizationSnapshot
    consumed*: int
  ## Preflight arithmetic records no source pointer or partially constructed owner.
  Layout = object
    bytes: int
    hashes: uint64

func error*[T](value: AuthorizationResult[T]): AuthorizationError =
  ## Failure reasons do not authorize entries, owners, hashes, counts or consumed progress.
  value.status
func value*[T](value: AuthorizationResult[T]): T {.inline, requires: value.status ==
    AuthorizationError.None.} =
  ## Public and internal completed values require explicit successful selection in optimized builds too.
  value.completed

## Validate configuration-derived descriptor and minimum wire extents without multiplying untrusted sizes.
proc validate(kind: AuthorizationKind, config: AuthorizationConfig): AuthorizationError =
  # The nightly permits unchecked enum casts; no other representation may select a namespace or row schema.
  if ord(kind) > ord(AuthorizationKind.Queues):
    return AuthorizationError.InvalidTag
  if uint64(config.cores) < 2:
    return AuthorizationError.InvalidConfig # JAM's validator/core population requires at least two cores.
  let minimum = if kind == AuthorizationKind.Pools: 1 else: 80*32 # One pool count versus a complete fixed queue per core.
  if uint64(config.cores) > uint64(high(int) div sizeof(AuthorizerRow)) or
      uint64(config.cores) > uint64(high(int) div minimum):
    return AuthorizationError.LengthOverflow # Bound descriptor storage and minimum wire size before native conversion.
  if uint64(config.cores)*uint64(minimum) > uint64(config.maxBytes):
    return AuthorizationError.LimitExceeded # Even empty pools require one count byte per configured core.
  AuthorizationError.None

## Charge a row's protocol cardinality, aggregate hash budget and full framed byte extent.
proc charge(kind: AuthorizationKind, count: uint64, prefix: int, config: AuthorizationConfig,
            layout: var Layout): AuthorizationError =
  if (kind == AuthorizationKind.Pools and count > 8) or
      (kind == AuthorizationKind.Queues and count != 80):
    return AuthorizationError.InvalidCount # Pools allow 0..8; queues have exactly 80, without deduplication.
  if count > uint64(config.maxHashes)-layout.hashes:
    return AuthorizationError.LimitExceeded # Subtract before summing aggregate hash work/storage.
  if prefix > high(int)-layout.bytes:
    return AuthorizationError.LengthOverflow # Count framing itself must fit before subtracting it.
  if count > uint64((high(int)-layout.bytes-prefix) div 32):
    return AuthorizationError.LengthOverflow # Fixed record multiplication must fit the remaining native extent.
  layout.bytes += prefix+int(count)*32
  layout.hashes += count
  if uint64(layout.bytes) > uint64(config.maxBytes):
    return AuthorizationError.LimitExceeded # Policy includes all pool count prefixes.
  AuthorizationError.None

## Read canonical pool counts, mapping primitive framing failures without exposing partial progress.
proc poolCount(input: openArray[byte]): AuthorizationResult[tuple[count: uint64, prefix: int]] =
  let parsed = codec_natural.decode(input)
  if not parsed.ok:
    # Incomplete counts and complete overlong forms remain distinct failure-only results.
    if parsed.error == DecodeError.truncated:
      return AuthorizationResult[tuple[count: uint64, prefix: int]](
          status: AuthorizationError.Truncated) # No count available yet.
    else:
      return AuthorizationResult[tuple[count: uint64, prefix: int]](
          status: AuthorizationError.NonCanonical) # Reject second encodings.
  AuthorizationResult[tuple[count: uint64, prefix: int]](status: AuthorizationError.None,
    completed: (uint64(parsed.value), int(parsed.consumed)))

proc authorizationEntry*(kind: AuthorizationKind, rows: openArray[AuthorizerRow],
                         config: AuthorizationConfig): AuthorizationResult[StateEntry] =
  ## Emit chapter 1/2 from stable caller rows after whole-component shape/resource preflight.
  let valid = validate(kind, config)
  if valid != AuthorizationError.None:
    return AuthorizationResult[StateEntry](status: valid) # Invalid configuration never allocates payload storage.
  if uint64(rows.len) != uint64(config.cores):
    return AuthorizationResult[StateEntry](status: AuthorizationError.InvalidCount) # Outer cardinality is implicit and exact.
  var layout = default(Layout)
  # Validate even the final row before allocating or serializing any earlier row.
  for row in rows:
    var prefix = 0
    if kind == AuthorizationKind.Pools:
      prefix = int(codec_natural.encode(JamNatural(
          row.len)).len) # Pools alone carry a positive count-prefix extent.
    let error = charge(kind, uint64(row.len), prefix, config, layout)
    if error != AuthorizationError.None:
      return AuthorizationResult[StateEntry](status: error) # No partial output on shape/policy failure.
  let chapter = if kind == AuthorizationKind.Pools: 1 else: 2 # Namespaces distinguish identical underlying hashes.
  var entry = StateEntry(key: chapterKey(StateChapter(chapter)), value: newSeq[byte](layout.bytes))
  var cursor = 0
  # Preserve both core order and per-core insertion/queue order, including repeated hashes.
  for row in rows:
    if kind == AuthorizationKind.Pools:
      # General-natural framing applies to each pool, never the whole core sequence.
      let count = codec_natural.encode(JamNatural(row.len))
      for i in 0..<count.len:
        entry.value[cursor] = count.bytes[i]
        inc cursor
    # Fixed queues and framed pools then share the same opaque 32-byte hash layout.
    for hash in row:
      for b in hash.bytes:
        entry.value[cursor] = b # Copy octets into independent entry storage.
        inc cursor
  AuthorizationResult[StateEntry](status: AuthorizationError.None, completed: entry)

proc decodeAuthorization*(kind: AuthorizationKind, input: openArray[byte],
                          config: AuthorizationConfig): AuthorizationResult[AuthorizationRead] =
  ## Decode one complete component prefix into immutable copied storage after a no-allocation validation pass.
  let valid = validate(kind, config)
  if valid != AuthorizationError.None:
    return AuthorizationResult[AuthorizationRead](
        status: valid) # Configuration cannot authorize unsafe native extents.
  var layout = default(Layout)
  # Prove every count, row extent and aggregate ceiling before allocating snapshot descriptors or hashes.
  for core in 0..<int(uint64(config.cores)):
    var count = 80'u64
    var prefix = 0
    if kind == AuthorizationKind.Pools:
      # Earlier complete rows guarantee a safe borrowed suffix for the next canonical count.
      let parsed = poolCount(input.toOpenArray(layout.bytes, input.len-1))
      if parsed.error != AuthorizationError.None:
        return AuthorizationResult[AuthorizationRead](status: parsed.error) # No earlier row owner escapes.
      count = parsed.value.count
      prefix = parsed.value.prefix
    let error = charge(kind, count, prefix, config, layout)
    if error != AuthorizationError.None:
      return AuthorizationResult[AuthorizationRead](
          status: error) # Reject announced work before touching its payload.
    if input.len < layout.bytes:
      return AuthorizationResult[AuthorizationRead](
          status: AuthorizationError.Truncated) # No padding/default hashes on missing bytes.
  let data = AuthorizationData(kind: kind, rows: newSeq[AuthorizerRow](int(uint64(config.cores))))
  let owner = AuthorizationSnapshot(data: data)
  var cursor = 0
  # The stable borrowed input is now fully validated; copy only its committed prefix into the private owner.
  for core in 0..<data.rows.len:
    var count = 80
    if kind == AuthorizationKind.Pools:
      # Re-read validated framing without retaining offsets detached from the owner.
      let parsed = poolCount(input.toOpenArray(cursor, input.len-1))
      assert parsed.error == AuthorizationError.None # Full preflight and stable input prove the repeated parse succeeds.
      count = int(parsed.value.count)
      cursor += parsed.value.prefix
    data.rows[core] = newSeq[AuthorizerHash](count)
    # Each hash is a fixed independent value, not a borrowed slice into the original wire.
    for i in 0..<count:
      for j in 0..<32:
        data.rows[core][i].bytes[j] = input[cursor] # Full preflight established all accesses.
        inc cursor
  AuthorizationResult[AuthorizationRead](status: AuthorizationError.None,
    completed: AuthorizationRead(snapshot: owner, consumed: cursor))

proc authorizationKind*(owner: AuthorizationSnapshot): AuthorizationResult[AuthorizationKind] =
  ## Inspect the retained component kind, rejecting default handles rather than inventing an empty pool.
  let data = owner.data
  if data == nil:
    return AuthorizationResult[AuthorizationKind](
        status: AuthorizationError.InvalidOwner) # No validated kind on default handles.
  AuthorizationResult[AuthorizationKind](status: AuthorizationError.None, completed: data.kind)

proc authorizationCores*(owner: AuthorizationSnapshot): AuthorizationResult[int] =
  ## Count configured core rows without exporting the owner's private nested sequences.
  let data = owner.data
  if data == nil:
    return AuthorizationResult[int](status: AuthorizationError.InvalidOwner) # No population on absent storage.
  AuthorizationResult[int](status: AuthorizationError.None, completed: data.rows.len)

proc authorizerCount*(owner: AuthorizationSnapshot,
    core: AuthorizationCoreIndex): AuthorizationResult[int] =
  ## Inspect one owner's row size after checking its nominal core ordinal.
  let data = owner.data
  if data == nil:
    return AuthorizationResult[int](status: AuthorizationError.InvalidOwner) # Never dereference default snapshots.
  if uint64(core) >= uint64(data.rows.len):
    return AuthorizationResult[int](status: AuthorizationError.InvalidIndex) # Check before native indexing.
  AuthorizationResult[int](status: AuthorizationError.None, completed: data.rows[int(uint64(core))].len)

proc authorizerAt*(owner: AuthorizationSnapshot, core: AuthorizationCoreIndex,
                   index: AuthorizationIndex): AuthorizationResult[AuthorizerHash] =
  ## Extract a copied authorizer hash through its retained core owner and nominal row position.
  let data = owner.data
  # Bind and validate the same retained storage used for final hash extraction.
  if data == nil:
    return AuthorizationResult[AuthorizerHash](status: AuthorizationError.InvalidOwner)
  let count = authorizerCount(owner, core)
  if count.error != AuthorizationError.None:
    return AuthorizationResult[AuthorizerHash](status: count.error) # Invalid owners/cores expose no hash.
  if uint64(index) >= uint64(count.value):
    return AuthorizationResult[AuthorizerHash](status: AuthorizationError.InvalidIndex) # Check before narrowing the position.
  AuthorizationResult[AuthorizerHash](status: AuthorizationError.None,
    completed: data.rows[int(uint64(core))][int(uint64(index))])
