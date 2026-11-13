# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Incremental bounded CE139/140/148 group grammar shares no heap or canonical state with native callbacks.

import ../codec/natural

type
  SegmentRequestKind* {.pure.} = enum ## Wire selectors distinguish raw shards, authenticated shards and original segments.
    Shards = 139, ProvenShards = 140, Segments = 148
  SegmentRequestError* {.pure.} = enum ## A partial/default cursor cannot certify complete input.
    Uninitialized, None, InvalidFormat, LimitExceeded
  SegmentRequestResult*[T] = object ## Failure never exposes a partially parsed coordinate list.
    case status: SegmentRequestError
    of None: completed: T
    else: discard                   # Only complete validated input carries selections.
  Phase {.pure.} = enum ## Each transition consumes one byte and performs at most nine natural-prefix steps.
    Root, Shard, Count, Index
  SegmentRequestCursor* = object ## Fixed scratch and bounded scalar counts make fragmented parsing independent of input extent.
    ready: bool
    kind: SegmentRequestKind
    phase: Phase
    used, groups, items, prefixUsed, prefixSize: int
    remaining: uint64
    prefix: array[9, byte]
    failure: SegmentRequestError
  SegmentSelection* = object ## Detached copied coordinates retain exact input order, including duplicate requests.
    root*: array[32, byte]
    shard*, index*: uint16

func maximumItems*(kind: SegmentRequestKind): int =
  ## Pinned NP maxima apply to the complete stream, not to each group separately.
  if kind == SegmentRequestKind.Segments: 3072 else: 6144

func maximumPayload*(kind: SegmentRequestKind): int =
  ## Group count is independently capped even when groups contain no indices.
  kind.maximumItems*45

func initSegmentRequestCursor*(kind: SegmentRequestKind): SegmentRequestCursor =
  ## Empty input is a complete empty sequence; no guessed group or element exists by default.
  SegmentRequestCursor(ready: true, kind: kind, failure: SegmentRequestError.None)

func complete*(cursor: SegmentRequestCursor): bool =
  ## Exact group boundaries distinguish successful empty sequences from truncated roots/counts/indices.
  cursor.ready and cursor.failure == SegmentRequestError.None and cursor.phase == Phase.Root and
      cursor.used == 0

func itemCount*(cursor: SegmentRequestCursor): int =
  ## Detached scalar metadata is safe to inspect without retaining a partial payload.
  cursor.items

func groupCount*(cursor: SegmentRequestCursor): int =
  ## Empty-list groups still consume a finite independent parser resource.
  cursor.groups

proc consume*(cursor: var SegmentRequestCursor, octet: byte): SegmentRequestError =
  ## Validate one byte without allocation; failures remain terminal and never yield an accepted prefix.
  if not cursor.ready: return SegmentRequestError.Uninitialized
  if cursor.failure != SegmentRequestError.None: return cursor.failure
  case cursor.phase
  of Phase.Root:
    if cursor.used == 0:
      if cursor.groups >= cursor.kind.maximumItems:
        cursor.failure = SegmentRequestError.LimitExceeded
        return cursor.failure
      inc cursor.groups
    inc cursor.used
    if cursor.used == 32:
      cursor.used = 0
      cursor.phase = if cursor.kind == SegmentRequestKind.Segments: Phase.Count else: Phase.Shard
  of Phase.Shard:
    inc cursor.used
    if cursor.used == 2:
      cursor.used = 0
      cursor.phase = Phase.Count
  of Phase.Count:
    if cursor.prefixUsed == 0:
      cursor.prefixSize = 1
      var mask = 128
      while mask > 0 and (int(octet) and mask) != 0:
        inc cursor.prefixSize
        mask = mask shr 1
    cursor.prefix[cursor.prefixUsed] = octet
    inc cursor.prefixUsed
    if cursor.prefixUsed == cursor.prefixSize:
      let decoded = decode(cursor.prefix.toOpenArray(0, cursor.prefixUsed-1))
      if not decoded.ok:
        cursor.failure = SegmentRequestError.InvalidFormat
        return cursor.failure
      let count = uint64(decoded.value)
      if count > uint64(cursor.kind.maximumItems-cursor.items):
        cursor.failure = SegmentRequestError.LimitExceeded
        return cursor.failure
      cursor.items += int(count)
      cursor.remaining = count
      cursor.prefixUsed = 0
      cursor.phase = if count == 0: Phase.Root else: Phase.Index
  of Phase.Index:
    inc cursor.used
    if cursor.used == 2:
      cursor.used = 0
      dec cursor.remaining
      if cursor.remaining == 0: cursor.phase = Phase.Root
  SegmentRequestError.None

proc segmentSelections*(kind: SegmentRequestKind, payload: openArray[byte]): SegmentRequestResult[
    seq[SegmentSelection]] =
  ## Call only after exact cursor validation; copied ordered coordinates contain no payload alias or native pointer.
  if payload.len > kind.maximumPayload: return SegmentRequestResult[seq[SegmentSelection]](
      status: SegmentRequestError.LimitExceeded)
  var cursor = initSegmentRequestCursor(kind)
  for octet in payload:
    let reason = cursor.consume(octet)
    if reason != SegmentRequestError.None: return SegmentRequestResult[seq[SegmentSelection]](status: reason)
  if not cursor.complete: return SegmentRequestResult[seq[SegmentSelection]](
      status: SegmentRequestError.InvalidFormat)
  var selections = newSeq[SegmentSelection](cursor.itemCount)
  var offset, ordinal = 0
  while offset < payload.len:
    let prefix = if kind == SegmentRequestKind.Segments: 32 else: 34
    if payload.len-offset <= prefix:
      return SegmentRequestResult[seq[SegmentSelection]](status: SegmentRequestError.InvalidFormat)
    var selected = default(SegmentSelection)
    for index in 0..<32: selected.root[index] = payload[offset+index]
    offset += 32
    if kind != SegmentRequestKind.Segments:
      selected.shard = uint16(payload[offset]) or (uint16(payload[offset+1]) shl 8)
      offset += 2
    let count = decode(payload.toOpenArray(offset, payload.len-1))
    if not count.ok:
      return SegmentRequestResult[seq[SegmentSelection]](status: SegmentRequestError.InvalidFormat)
    offset += count.consumed
    let items = uint64(count.value)
    if items > uint64((payload.len-offset) div 2) or items > uint64(selections.len-ordinal):
      return SegmentRequestResult[seq[SegmentSelection]](status: SegmentRequestError.InvalidFormat)
    for index in 0..<int(items):
      selected.index = uint16(payload[offset]) or (uint16(payload[offset+1]) shl 8)
      offset += 2
      selections[ordinal] = selected
      inc ordinal
  if ordinal != selections.len:
    return SegmentRequestResult[seq[SegmentSelection]](status: SegmentRequestError.InvalidFormat)
  SegmentRequestResult[seq[SegmentSelection]](status: SegmentRequestError.None,
      completed: selections)

func error*[T](outcome: SegmentRequestResult[T]): SegmentRequestError =
  ## Inspect the status before selecting any complete ordered coordinates.
  outcome.status

func value*[T](outcome: SegmentRequestResult[T]): T {.requires: outcome.status ==
    SegmentRequestError.None.} =
  ## A default/truncated request cannot expose an accepted prefix.
  outcome.completed
