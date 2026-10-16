## GP 0.8.0 T(state) chapters 1/2 and authorization eq:authstatecomposition.
## Entries encode ordered core pools/queues; no authorization or state transition is executed.
import ./[natural, bounded, assurances, state_layout, state_trie]
from ./work_report import AuthorizerHash
export AuthorizerHash

type
  ## Distinguishes variable pools (chapter 1) from fixed queues (chapter 2).
  AuthorizationKind* {.pure.} = enum
    Pools, Queues
  ## Synchronous borrowed source row; neither its backing storage nor any mutable alias is retained.
  AuthorizerRow* = seq[AuthorizerHash]
  ## An ordinal in the configured core sequence, distinct from an authorizer position.
  AuthorizationCoreIndex* = distinct uint64
  ## A position within one core's ordered pool or queue.
  AuthorizationIndex* = distinct uint64
  ## Explicit chain cardinality and caller ceilings for total hashes and complete payload bytes.
  AuthorizationConfig* = object
    cores*: CoreCount
    maxHashes*: ElementLimit
    maxBytes*: ByteLimit
  ## Failed/default results have no entry, owner, count or consumed cursor.
  AuthorizationError* {.pure.} = enum
    Uninitialized, None, InvalidConfig, InvalidCount, Truncated, NonCanonical,
    LimitExceeded, LengthOverflow, InvalidOwner, InvalidIndex
  ## Only success exposes the complete selected application value.
  AuthorizationResult*[T] = object
    case error*: AuthorizationError
    of AuthorizationError.None:
      value*: T # Complete success alone carries application data.
    else:
      discard   # No default value or partial progress on failure.
  ## Private acyclic ARC storage binds ordered copied hashes to their validated component kind.
  AuthorizationData = ref object
    kind: AuthorizationKind
    rows: seq[AuthorizerRow]
  ## Value handle shares immutable private storage; replacing a handle cannot mutate other copies.
  AuthorizationSnapshot* = object
    data: AuthorizationData
  ## Complete prefix decoding carries its immutable snapshot and exact consumed byte extent.
  AuthorizationRead* = object
    snapshot*: AuthorizationSnapshot
    consumed*: int
  ## Preflight arithmetic records no source pointer or partially constructed owner.
  Layout = object
    bytes: int
    hashes: uint64

## Validate configuration-derived descriptor and minimum wire extents without multiplying untrusted sizes.
proc validate(kind: AuthorizationKind, config: AuthorizationConfig): AuthorizationError =
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
  let parsed = natural.decode(input)
  if not parsed.ok:
    # Incomplete counts and complete overlong forms remain distinct failure-only results.
    if parsed.error == DecodeError.truncated:
      return AuthorizationResult[tuple[count: uint64, prefix: int]](
          error: AuthorizationError.Truncated) # No count available yet.
    else:
      return AuthorizationResult[tuple[count: uint64, prefix: int]](
          error: AuthorizationError.NonCanonical) # Reject second encodings.
  AuthorizationResult[tuple[count: uint64, prefix: int]](error: AuthorizationError.None,
    value: (uint64(parsed.value), int(parsed.consumed)))

## Emit chapter 1/2 from stable caller rows after whole-component shape/resource preflight.
proc authorizationEntry*(kind: AuthorizationKind, rows: openArray[AuthorizerRow],
                         config: AuthorizationConfig): AuthorizationResult[StateEntry] =
  let valid = validate(kind, config)
  if valid != AuthorizationError.None:
    return AuthorizationResult[StateEntry](error: valid) # Invalid configuration never allocates payload storage.
  if uint64(rows.len) != uint64(config.cores):
    return AuthorizationResult[StateEntry](error: AuthorizationError.InvalidCount) # Outer cardinality is implicit and exact.
  var layout: Layout
  # Validate even the final row before allocating or serializing any earlier row.
  for row in rows:
    var prefix = 0
    if kind == AuthorizationKind.Pools:
      prefix = int(natural.encode(JamNatural(row.len)).len) # Pools alone carry a positive count-prefix extent.
    let error = charge(kind, uint64(row.len), prefix, config, layout)
    if error != AuthorizationError.None:
      return AuthorizationResult[StateEntry](error: error) # No partial output on shape/policy failure.
  let chapter = if kind == AuthorizationKind.Pools: 1 else: 2 # Namespaces distinguish identical underlying hashes.
  var entry = StateEntry(key: chapterKey(StateChapter(chapter)), value: newSeq[byte](layout.bytes))
  var cursor = 0
  # Preserve both core order and per-core insertion/queue order, including repeated hashes.
  for row in rows:
    if kind == AuthorizationKind.Pools:
      # General-natural framing applies to each pool, never the whole core sequence.
      let count = natural.encode(JamNatural(row.len))
      for i in 0..<count.len:
        entry.value[cursor] = count.bytes[i]
        inc cursor
    # Fixed queues and framed pools then share the same opaque 32-byte hash layout.
    for hash in row:
      for b in hash.bytes:
        entry.value[cursor] = b # Copy octets into independent entry storage.
        inc cursor
  AuthorizationResult[StateEntry](error: AuthorizationError.None, value: entry)

## Decode one complete component prefix into immutable copied storage after a no-allocation validation pass.
proc decodeAuthorization*(kind: AuthorizationKind, input: openArray[byte],
                          config: AuthorizationConfig): AuthorizationResult[AuthorizationRead] =
  let valid = validate(kind, config)
  if valid != AuthorizationError.None:
    return AuthorizationResult[AuthorizationRead](
        error: valid) # Configuration cannot authorize unsafe native extents.
  var layout: Layout
  # Prove every count, row extent and aggregate ceiling before allocating snapshot descriptors or hashes.
  for core in 0..<int(uint64(config.cores)):
    var count = 80'u64
    var prefix = 0
    if kind == AuthorizationKind.Pools:
      # Earlier complete rows guarantee a safe borrowed suffix for the next canonical count.
      let parsed = poolCount(input.toOpenArray(layout.bytes, input.len-1))
      if parsed.error != AuthorizationError.None:
        return AuthorizationResult[AuthorizationRead](error: parsed.error) # No earlier row owner escapes.
      count = parsed.value.count
      prefix = parsed.value.prefix
    let error = charge(kind, count, prefix, config, layout)
    if error != AuthorizationError.None:
      return AuthorizationResult[AuthorizationRead](
          error: error) # Reject announced work before touching its payload.
    if input.len < layout.bytes:
      return AuthorizationResult[AuthorizationRead](
          error: AuthorizationError.Truncated) # No padding/default hashes on missing bytes.
  let owner = AuthorizationSnapshot(data: AuthorizationData(kind: kind,
    rows: newSeq[AuthorizerRow](int(uint64(config.cores)))))
  var cursor = 0
  # The stable borrowed input is now fully validated; copy only its committed prefix into the private owner.
  for core in 0..<owner.data.rows.len:
    var count = 80
    if kind == AuthorizationKind.Pools:
      # Re-read validated framing without retaining offsets detached from the owner.
      let parsed = poolCount(input.toOpenArray(cursor, input.len-1))
      doAssert parsed.error == AuthorizationError.None # Full preflight and stable input prove the repeated parse succeeds.
      count = int(parsed.value.count)
      cursor += parsed.value.prefix
    owner.data.rows[core] = newSeq[AuthorizerHash](count)
    # Each hash is a fixed independent value, not a borrowed slice into the original wire.
    for i in 0..<count:
      for j in 0..<32:
        owner.data.rows[core][i].bytes[j] = input[cursor] # Full preflight established all accesses.
        inc cursor
  AuthorizationResult[AuthorizationRead](error: AuthorizationError.None,
    value: AuthorizationRead(snapshot: owner, consumed: cursor))

## Inspect the retained component kind, rejecting default handles rather than inventing an empty pool.
proc authorizationKind*(owner: AuthorizationSnapshot): AuthorizationResult[AuthorizationKind] =
  if owner.data.isNil:
    return AuthorizationResult[AuthorizationKind](
        error: AuthorizationError.InvalidOwner) # No validated kind on default handles.
  AuthorizationResult[AuthorizationKind](error: AuthorizationError.None, value: owner.data.kind)

## Count configured core rows without exporting the owner's private nested sequences.
proc authorizationCores*(owner: AuthorizationSnapshot): AuthorizationResult[int] =
  if owner.data.isNil:
    return AuthorizationResult[int](error: AuthorizationError.InvalidOwner) # No population on absent storage.
  AuthorizationResult[int](error: AuthorizationError.None, value: owner.data.rows.len)

## Inspect one owner's row size after checking its nominal core ordinal.
proc authorizerCount*(owner: AuthorizationSnapshot,
    core: AuthorizationCoreIndex): AuthorizationResult[int] =
  if owner.data.isNil:
    return AuthorizationResult[int](error: AuthorizationError.InvalidOwner) # Never dereference default snapshots.
  if uint64(core) >= uint64(owner.data.rows.len):
    return AuthorizationResult[int](error: AuthorizationError.InvalidIndex) # Check before native indexing.
  AuthorizationResult[int](error: AuthorizationError.None, value: owner.data.rows[int(uint64(core))].len)

## Extract a copied authorizer hash through its retained core owner and nominal row position.
proc authorizerAt*(owner: AuthorizationSnapshot, core: AuthorizationCoreIndex,
                   index: AuthorizationIndex): AuthorizationResult[AuthorizerHash] =
  let count = authorizerCount(owner, core)
  if count.error != AuthorizationError.None:
    return AuthorizationResult[AuthorizerHash](error: count.error) # Invalid owners/cores expose no hash.
  if uint64(index) >= uint64(count.value):
    return AuthorizationResult[AuthorizerHash](error: AuthorizationError.InvalidIndex) # Check before narrowing the position.
  AuthorizationResult[AuthorizerHash](error: AuthorizationError.None,
    value: owner.data.rows[int(uint64(core))][int(uint64(index))])
