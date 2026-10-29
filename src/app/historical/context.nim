# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Canonical local context selects one scalar historical index alongside the bounded live chain view.
## The enclosing ordinary journal/paged publication supplies durable authority; nested wrappers are forbidden.
import ../../storage/history/index as history_index
import ../../storage/database_identity
import ../../codec/bounded

const
  ContextMagic = "RAGNAROK-DISK-HISTORY-V1\n"
  HistoricalContextPrefixBytes* = ContextMagic.len+HistoryCursorBytes+8
type HistoricalContext* = object ## Private copied bytes contain only the bounded live context, never a resident archive list.
  cursor: HistoryCursor
  live: seq[byte]

func hasHistoricalContext*(bytes: openArray[byte]): bool =
  ## Exact prefix recognition never accepts an unknown version as another historical format.
  if bytes.len < ContextMagic.len: return false
  for index, character in ContextMagic:
    if bytes[index] != byte(character): return false
  true
func historicalCursor*(context: HistoricalContext): HistoryCursor =
  ## Default contexts return a default uninitialized cursor, which grants no file access.
  context.cursor
proc chainContext*(context: HistoricalContext): seq[byte] =
  ## Copy only the bounded rolling context; the archive itself stays on disk.
  context.live
proc encodeHistoricalContext*(cursor: HistoryCursor, live: openArray[byte],
    limit: ByteLimit): HistoryResult[seq[byte]] =
  ## Admit the full output before allocating or copying any live header/body payload.
  if not cursor.initialized or uint64(cursor.lastOrdinal) == 0:
    return historyFailure[seq[byte]](HistoryError.Uninitialized)
  let maximum = min(uint64(limit), uint64(high(int)))
  if uint64(HistoricalContextPrefixBytes) > maximum or
      uint64(live.len) > maximum-uint64(HistoricalContextPrefixBytes):
    return historyFailure[seq[byte]](HistoryError.LimitExceeded)
  if live.len == 0 or hasHistoricalContext(live): return historyFailure[seq[byte]](
      HistoryError.InvalidFormat)
  let encoded = encodeHistoryCursor(cursor)
  if encoded.error != HistoryError.None: return historyFailure[seq[byte]](encoded.error)
  var bytes = newSeq[byte](HistoricalContextPrefixBytes+live.len)
  for index, character in ContextMagic: bytes[index] = byte(character)
  for index, octet in encoded.value: bytes[ContextMagic.len+index] = octet
  let offset = ContextMagic.len+HistoryCursorBytes
  for index in 0..<8: bytes[offset+index] = byte((uint64(live.len) shr (index*8)) and 255)
  for index, octet in live: bytes[HistoricalContextPrefixBytes+index] = octet
  historySuccess(bytes)
proc decodeHistoricalContext*(bytes: openArray[byte], chain: StorageChainId,
    limit: ByteLimit): HistoryResult[HistoricalContext] =
  ## Fixed bounds and exact remaining extent precede bounded payload allocation; recursion cannot grow with disk bytes.
  if uint64(bytes.len) > uint64(limit): return historyFailure[HistoricalContext](
      HistoryError.LimitExceeded)
  if bytes.len <= HistoricalContextPrefixBytes or not hasHistoricalContext(bytes):
    return historyFailure[HistoricalContext](HistoryError.InvalidFormat)
  let cursor = decodeHistoryCursor(bytes.toOpenArray(ContextMagic.len,
    ContextMagic.len+HistoryCursorBytes-1), chain)
  if cursor.error != HistoryError.None: return historyFailure[HistoricalContext](cursor.error)
  if uint64(cursor.value.lastOrdinal) == 0: return historyFailure[HistoricalContext](
      HistoryError.InvalidFormat)
  let offset = ContextMagic.len+HistoryCursorBytes
  var length = 0'u64
  for index in 0..<8: length = length or (uint64(bytes[offset+index]) shl (index*8))
  if length != uint64(bytes.len-HistoricalContextPrefixBytes):
    return historyFailure[HistoricalContext](HistoryError.InvalidFormat)
  let live = bytes.toOpenArray(HistoricalContextPrefixBytes, bytes.high)
  if hasHistoricalContext(live): return historyFailure[HistoricalContext](
      HistoryError.InvalidFormat)
  var copied = newSeq[byte](int(length)) # Equality with the input remainder proves host conversion/allocation bounds.
  for index, octet in live: copied[index] = octet
  historySuccess(HistoricalContext(cursor: cursor.value, live: copied))
