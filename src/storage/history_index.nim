# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Constant-size historical selection and append-only index rows bind accepted block/state identities.
## The selected digest authenticates the retained row suffix; policy expansion never backfills pruned rows.
import ./database_identity
import ../codec/state_trie
import ../crypto/primitives

const
  HistoryCursorBytes* = 160 ## Fixed versioned policy/selection, independent of historical length.
  HistoryRowBytes* = 240    ## Fixed ordinal index; complete states and bodies live in independent records.
  CursorMagic = "RAGNAROK-HISTORY-CURSOR-V1\n"
  RowMagic = "RAGNAROK-HISTORY-ROW-V1\n"
type
  HistoryError* {.pure.} = enum ## Refusals never expose a partial selection, record or successful IO prefix.
    Uninitialized, None, InvalidPolicy, InvalidFormat, LimitExceeded, CounterExhausted,
    NotChild, SlotNotIncreasing, BackendFailure, ChecksumMismatch, Unavailable, Pruned,
    IoFailure, PublishedUnsynced, WrongChain, StaleSelection
  HistoryResult*[T] = object ## Only complete success grants an owned payload.
    case status: HistoryError
    of None: completed: T
    else: discard            # Defaults and failed results retain only their typed reason.
  HistoryOrdinal* = distinct uint64 ## Positive local acceptance ordinal; not a slot or repository generation.
  HistoryBlockHash* = distinct array[32, byte] ## Full sealed-header identity, never a complete-state root.
  HistoryDigest* = distinct array[32, byte] ## Local index authentication, independent of JAM Merklization.
  HistoryPolicy* = object ## Private validated selection; zero keep means archive only when initialized.
    ready: bool
    keep: uint64
  HistoryCursor* = object ## Immutable scalar selection owns no historical list, cache or native descriptor.
    ready: bool
    policy: HistoryPolicy
    first, last: uint64
    chain: StorageChainId
    selected: HistoryBlockHash
    slot: uint32
    digest: HistoryDigest
  HistoryRow* = object ## Private immutable row commits exact block bytes when available and complete state identity.
    ready, body: bool
    ordinal: uint64
    slot: uint32
    selected, parent: HistoryBlockHash
    root: StateRoot
    bodyDigest: HistoryDigest
    previous, digest: HistoryDigest
  HistoryAppend* = object ## A staged row plus successor cursor; staging performs no IO or canonical publication.
    ready: bool
    before, after: HistoryCursor
    row: HistoryRow

func `==`*(left, right: HistoryDigest): bool =
  ## Compare all 256 local authentication bits without crossing into JAM root domains.
  array[32, byte](left) == array[32, byte](right)
func `==`*(left, right: HistoryBlockHash): bool =
  ## Historical block identities compare only within their nominal full-header domain.
  array[32, byte](left) == array[32, byte](right)
func `==`*(left, right: HistoryOrdinal): bool =
  ## Local acceptance ordinals never implicitly compare with slots or repository generations.
  uint64(left) == uint64(right)
func `<`*(left, right: HistoryOrdinal): bool =
  ## Order positive local acceptance counters without arithmetic or narrowing.
  uint64(left) < uint64(right)
func `<=`*(left, right: HistoryOrdinal): bool =
  ## Include equality in nominal ordinal bounds checks.
  uint64(left) <= uint64(right)

func error*[T](outcome: HistoryResult[T]): HistoryError =
  ## Read failure without exposing an inactive payload.
  outcome.status
func value*[T](outcome: HistoryResult[T]): T {.requires: outcome.status == HistoryError.None.} =
  ## Extract only a complete successful payload.
  outcome.completed
func historySuccess*[T](value: sink T): HistoryResult[T] =
  ## Let owning layers return an already validated payload through the same guarded result shape.
  HistoryResult[T](status: HistoryError.None, completed: value)
func historyFailure*[T](reason: HistoryError): HistoryResult[T] {.requires: reason !=
    HistoryError.None.} =
  ## Construct a reason-only refusal, never a default successful value.
  HistoryResult[T](status: reason)
func initialized*(policy: HistoryPolicy): bool =
  ## Defaults grant no retention selection.
  policy.ready
func archiveHistoryPolicy*(): HistoryPolicy =
  ## Preserve all future accepted records without promising to restore an already pruned prefix.
  HistoryPolicy(ready: true)
func boundedHistoryPolicy*(count: uint64): HistoryResult[HistoryPolicy] =
  ## Accept any positive local count without allocating count-sized memory.
  if count == 0: return historyFailure[HistoryPolicy](HistoryError.InvalidPolicy)
  historySuccess(HistoryPolicy(ready: true, keep: count))
func archive*(policy: HistoryPolicy): bool {.requires: policy.ready.} =
  ## Distinguish archive from the positive bounded window.
  policy.keep == 0
func retainedBlocks*(policy: HistoryPolicy): uint64 {.requires: policy.ready.} =
  ## Return zero only for archive; callers inspect archive rather than treating zero as a bounded count.
  policy.keep
func sameHistoryPolicy*(left, right: HistoryPolicy): bool =
  ## Defaults and initialized policies never compare as equivalent authority.
  left.ready and right.ready and left.keep == right.keep
func initialized*(cursor: HistoryCursor): bool =
  ## Default cursors carry no chain or selected history authority.
  cursor.ready
func initHistoryCursor*(chain: StorageChainId, policy: HistoryPolicy): HistoryResult[
    HistoryCursor] =
  ## Create an empty chain-bound selection under an already validated policy.
  if not policy.ready: return historyFailure[HistoryCursor](HistoryError.InvalidPolicy)
  historySuccess(HistoryCursor(ready: true, chain: chain, policy: policy))
func historyPolicy*(cursor: HistoryCursor): HistoryPolicy {.requires: cursor.ready.} =
  ## Retain only copied scalar policy.
  cursor.policy
func chainId*(cursor: HistoryCursor): StorageChainId {.requires: cursor.ready.} =
  ## Keep full-node historical namespaces bound to their selected chain.
  cursor.chain
func firstOrdinal*(cursor: HistoryCursor): HistoryOrdinal {.requires: cursor.ready.} =
  ## Zero belongs only to an initialized empty selection.
  HistoryOrdinal(cursor.first)
func lastOrdinal*(cursor: HistoryCursor): HistoryOrdinal {.requires: cursor.ready.} =
  ## The acceptance counter increases independently of slot gaps and physical repository generations.
  HistoryOrdinal(cursor.last)
func selectedHash*(cursor: HistoryCursor): HistoryBlockHash {.requires: cursor.ready.} =
  ## Empty selections expose the zero scalar, never a usable historical record.
  cursor.selected
func selectedSlot*(cursor: HistoryCursor): uint32 {.requires: cursor.ready.} =
  ## Return the exact selected head's slot when the selection is nonempty.
  cursor.slot
func selectedDigest*(cursor: HistoryCursor): HistoryDigest {.requires: cursor.ready.} =
  ## Bind the retained index suffix to canonical durable context.
  cursor.digest
func len*(cursor: HistoryCursor): uint64 {.requires: cursor.ready.} =
  ## Count retained ordinary entries; separately retained validation/finality anchors are not charged.
  if cursor.last == 0: 0'u64 else: cursor.last-cursor.first+1
func withHistoryPolicy*(cursor: HistoryCursor, policy: HistoryPolicy): HistoryResult[
    HistoryCursor] =
  ## Shrink the available suffix or grant future capacity; never lower the oldest available ordinal.
  if not cursor.ready: return historyFailure[HistoryCursor](HistoryError.Uninitialized)
  if not policy.ready: return historyFailure[HistoryCursor](HistoryError.InvalidPolicy)
  var selected = cursor
  selected.policy = policy
  if policy.keep > 0 and cursor.last >= policy.keep:
    let oldest = cursor.last-policy.keep+1 # Positive keep proves subtraction and the following addition.
    if oldest > selected.first: selected.first = oldest
  historySuccess(selected)
func initialized*(row: HistoryRow): bool =
  ## Default rows cannot authorize disk addressing or copied identities.
  row.ready
func ordinal*(row: HistoryRow): HistoryOrdinal {.requires: row.ready.} =
  ## Return the immutable row's positive local ordinal.
  HistoryOrdinal(row.ordinal)
func blockHash*(row: HistoryRow): HistoryBlockHash {.requires: row.ready.} =
  ## Return the exact complete sealed-header identity.
  row.selected
func parentHash*(row: HistoryRow): HistoryBlockHash {.requires: row.ready.} =
  ## An index parent is a claim checked against the immediately preceding selected row.
  row.parent
func stateRoot*(row: HistoryRow): StateRoot {.requires: row.ready.} =
  ## Complete historical state must be independently decoded/recomputed against this identity.
  row.root
func slot*(row: HistoryRow): uint32 {.requires: row.ready.} =
  ## Slot gaps do not imply missing acceptance ordinals.
  row.slot
func hasBody*(row: HistoryRow): bool {.requires: row.ready.} =
  ## Legacy/import seeds explicitly distinguish absent body bytes from an empty extrinsic.
  row.body
func bodyDigest*(row: HistoryRow): HistoryDigest {.requires: row.ready and row.body.} =
  ## Full-byte local identity must match before a historical body is returned.
  row.bodyDigest
func previousDigest*(row: HistoryRow): HistoryDigest {.requires: row.ready.} =
  ## The first retained row binds its pruned predecessor without retaining that predecessor's payload.
  row.previous
func rowDigest*(row: HistoryRow): HistoryDigest {.requires: row.ready.} =
  ## Return the row's cached local authentication digest.
  row.digest
func ready*(append: HistoryAppend): bool =
  ## Defaults authorize neither staging files nor advancing a cursor.
  append.ready
func previousCursor*(append: HistoryAppend): HistoryCursor {.requires: append.ready.} =
  ## Exact predecessor comparison prevents unrelated/older writers from using this append.
  append.before
func nextCursor*(append: HistoryAppend): HistoryCursor {.requires: append.ready.} =
  ## This scalar selection becomes authoritative only with confirmed canonical publication.
  append.after
func indexRow*(append: HistoryAppend): HistoryRow {.requires: append.ready.} =
  ## File staging consumes this exact checked row, never detached caller metadata.
  append.row
func putNumber(bytes: var openArray[byte], offset: int, number: uint64, width = 8) =
  ## All callers prove fixed destination extents; masks bound narrowing and shifts.
  for index in 0..<width: bytes[offset+index] = byte((number shr (index*8)) and 255)
func number(bytes: openArray[byte], offset: int, width = 8): uint64 =
  ## Fixed-size callers prove complete scalar extents before access.
  result = 0
  for index in 0..<width: result = result or (uint64(bytes[offset+index]) shl (index*8))
func putHash(bytes: var openArray[byte], offset: int, hash: array[32, byte]) =
  ## Copy fixed-width identities without retaining caller storage.
  for index in 0..<32: bytes[offset+index] = hash[index]
func hashAt(bytes: openArray[byte], offset: int): array[32, byte] =
  ## Every internal caller proves the complete fixed identity before copying it.
  result = default(array[32, byte])
  for index in 0..<32: result[index] = bytes[offset+index]
func matchesMagic(bytes: openArray[byte], magic: string): bool =
  ## Exact fixed-width zero padding has one canonical representation.
  for index in 0..<32:
    let expected = if index < magic.len: byte(magic[index]) else: 0'u8
    if bytes[index] != expected: return false
  true
func rowBytes(row: HistoryRow): array[HistoryRowBytes, byte] =
  ## Fixed encoding includes the cached digest only after all committed fields.
  result = default(array[HistoryRowBytes, byte])
  for index, character in RowMagic: result[index] = byte(character)
  putNumber(result, 32, row.ordinal)
  putNumber(result, 40, uint64(row.slot), 4)
  result[44] = if row.body: 1'u8 else: 0'u8
  putHash(result, 48, array[32, byte](row.selected))
  putHash(result, 80, array[32, byte](row.parent))
  putHash(result, 112, array[32, byte](row.root))
  putHash(result, 144, array[32, byte](row.bodyDigest))
  putHash(result, 176, array[32, byte](row.previous))
  putHash(result, 208, array[32, byte](row.digest))
proc prepareHistoryAppend*(cursor: HistoryCursor, hash, parent: HistoryBlockHash,
    root: StateRoot, slot: uint32, hasBody: bool,
    bodyDigest = default(HistoryDigest)): HistoryResult[HistoryAppend] =
  ## Bind one genuine caller-selected child before file staging; this does not verify consensus execution.
  if not cursor.ready: return historyFailure[HistoryAppend](HistoryError.Uninitialized)
  if cursor.last == high(uint64): return historyFailure[HistoryAppend](
      HistoryError.CounterExhausted)
  if cursor.last > 0:
    if array[32, byte](parent) != array[32, byte](cursor.selected):
      return historyFailure[HistoryAppend](HistoryError.NotChild)
    if slot <= cursor.slot: return historyFailure[HistoryAppend](HistoryError.SlotNotIncreasing)
  if not hasBody and array[32, byte](bodyDigest) != default(array[32, byte]):
    return historyFailure[HistoryAppend](HistoryError.InvalidFormat)
  var row = HistoryRow(ready: true, ordinal: cursor.last+1, slot: slot, selected: hash,
    parent: parent, root: root, body: hasBody, bodyDigest: bodyDigest, previous: cursor.digest)
  let encoded = rowBytes(row)
  let digest = blake2b256(encoded.toOpenArray(0, 207))
  if digest.error != CryptoError.None: return historyFailure[HistoryAppend](
      HistoryError.BackendFailure)
  row.digest = HistoryDigest(array[32, byte](digest.value))
  var selected = cursor
  selected.last = row.ordinal
  selected.selected = hash
  selected.slot = slot
  selected.digest = row.digest
  if selected.first == 0: selected.first = 1
  let bounded = withHistoryPolicy(selected, cursor.policy)
  if bounded.error != HistoryError.None: return historyFailure[HistoryAppend](bounded.error)
  historySuccess(HistoryAppend(ready: true, before: cursor, after: bounded.value, row: row))
func encodeHistoryCursor*(cursor: HistoryCursor): HistoryResult[array[HistoryCursorBytes, byte]] =
  ## Encode fixed context without allocating or traversing historical entries.
  if not cursor.ready: return historyFailure[array[HistoryCursorBytes, byte]](
      HistoryError.Uninitialized)
  var bytes = default(array[HistoryCursorBytes, byte])
  for index, character in CursorMagic: bytes[index] = byte(character)
  putNumber(bytes, 32, cursor.policy.keep)
  putNumber(bytes, 40, cursor.first)
  putNumber(bytes, 48, cursor.last)
  putHash(bytes, 56, array[32, byte](cursor.selected))
  putNumber(bytes, 88, uint64(cursor.slot), 4)
  putHash(bytes, 96, array[32, byte](cursor.digest))
  putHash(bytes, 128, array[32, byte](cursor.chain))
  historySuccess(bytes)
func sameHistoryCursor*(left, right: HistoryCursor): bool =
  ## Initialized exact scalar selections, including policy, are required for shared publication.
  if not left.ready or not right.ready: return false
  let a = encodeHistoryCursor(left)
  let b = encodeHistoryCursor(right)
  if a.error != HistoryError.None or b.error != HistoryError.None: return false
  a.value == b.value
func decodeHistoryCursor*(bytes: openArray[byte], chain: StorageChainId): HistoryResult[
    HistoryCursor] =
  ## Validate all counters and reserved bytes before admitting any cursor-supplied ordinal.
  if bytes.len != HistoryCursorBytes or not matchesMagic(bytes, CursorMagic):
    return historyFailure[HistoryCursor](HistoryError.InvalidFormat)
  for index in 92..<96:
    if bytes[index] != 0: return historyFailure[HistoryCursor](HistoryError.InvalidFormat)
  if hashAt(bytes, 128) != array[32, byte](chain): return historyFailure[HistoryCursor](
      HistoryError.WrongChain)
  let keep = number(bytes, 32)
  let first = number(bytes, 40)
  let last = number(bytes, 48)
  let hash = hashAt(bytes, 56)
  let slot = uint32(number(bytes, 88, 4))
  let digest = hashAt(bytes, 96)
  if last == 0:
    if first != 0 or slot != 0 or hash != default(array[32, byte]) or digest != default(array[32, byte]):
      return historyFailure[HistoryCursor](HistoryError.InvalidFormat)
  elif first == 0 or first > last or (keep > 0 and last-first+1 > keep):
    return historyFailure[HistoryCursor](HistoryError.InvalidFormat)
  historySuccess(HistoryCursor(ready: true, chain: chain, policy: HistoryPolicy(ready: true,
      keep: keep),
    first: first, last: last, selected: HistoryBlockHash(hash), slot: slot, digest: HistoryDigest(digest)))
func encodeHistoryRow*(row: HistoryRow): HistoryResult[array[HistoryRowBytes, byte]] =
  ## Re-emit only a fully authored or digest-checked immutable row.
  if not row.ready: return historyFailure[array[HistoryRowBytes, byte]](HistoryError.Uninitialized)
  historySuccess(rowBytes(row))
proc decodeHistoryRow*(bytes: openArray[byte]): HistoryResult[HistoryRow] =
  ## Shape and digest checks precede extraction; a corrupt row never becomes missing history.
  if bytes.len != HistoryRowBytes or not matchesMagic(bytes, RowMagic) or bytes[44] > 1:
    return historyFailure[HistoryRow](HistoryError.InvalidFormat)
  for index in 45..<48:
    if bytes[index] != 0: return historyFailure[HistoryRow](HistoryError.InvalidFormat)
  let ordinal = number(bytes, 32)
  if ordinal == 0: return historyFailure[HistoryRow](HistoryError.InvalidFormat)
  let body = hashAt(bytes, 144)
  if bytes[44] == 0 and body != default(array[32, byte]):
    return historyFailure[HistoryRow](HistoryError.InvalidFormat)
  let digest = blake2b256(bytes.toOpenArray(0, 207))
  if digest.error != CryptoError.None: return historyFailure[HistoryRow](
      HistoryError.BackendFailure)
  if array[32, byte](digest.value) != hashAt(bytes, 208):
    return historyFailure[HistoryRow](HistoryError.ChecksumMismatch)
  historySuccess(HistoryRow(ready: true, ordinal: ordinal, slot: uint32(number(bytes, 40, 4)),
    selected: HistoryBlockHash(hashAt(bytes, 48)), parent: HistoryBlockHash(hashAt(bytes, 80)),
    root: StateRoot(hashAt(bytes, 112)), body: bytes[44] == 1, bodyDigest: HistoryDigest(body),
    previous: HistoryDigest(hashAt(bytes, 176)), digest: HistoryDigest(hashAt(bytes, 208))))
