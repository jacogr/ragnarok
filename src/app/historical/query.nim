# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Explicit offline full-state queries use the ordinary exclusive database lease and return independently owned bytes.
## A query opens only an existing database, never listens, changes retention or falls back to genesis.
import ../[options, services, chain]
import ./disk as historical_disk
import ../checkpoint/codec as checkpoint_codec
import "./export" as historical_export
import ../../chain/[genesis, provider]
import ../../storage/history/index as history_index
import ../../state/store
import ../../codec/[bounded, header]
import ../../lib/json/writer as json_writer

proc hexadecimal(bytes: openArray[byte]): string {.requires: bytes.len <= high(int) div 2.} =
  ## Every caller bounds its complete header/body before doubling the exact output extent.
  const digits = "0123456789abcdef"
  result = newString(bytes.len*2)
  for index, octet in bytes:
    result[index*2] = digits[int(octet shr 4)]
    result[index*2+1] = digits[int(octet and 15)]

func nibble(character: char): byte =
  ## Validated canonical hash characters have exactly one interpretation.
  if character <= '9': byte(ord(character)-ord('0')) else: byte(ord(character)-ord('a')+10)

proc runHistoricalQuery*(options: Options): HistoryResult[JsonValue] {.raises.} =
  ## Return exact selected data or a typed unavailable/pruned/IO refusal; publication of an export is explicitly requested.
  if not options.valid or options.argumentCount != 1 or options.argument(1) != "history":
    return historyFailure[JsonValue](HistoryError.InvalidFormat)
  var owner = default(Services)
  defer: owner.close() # Every refusal joins the idle worker and releases its exclusive writer lease.
  if not owner.start(options, "history"): return historyFailure[JsonValue](HistoryError.IoFailure)
  var selected = default(HistoryResult[ApplicationChain])
  let hash = options.historicalHash
  if hash.len > 0:
    var bytes = default(array[32, byte])
    for index in 0..<32: bytes[index] = (nibble(hash[index*2]) shl 4) or nibble(hash[index*2+1])
    selected = owner.historicalSnapshot(BlockHash(bytes))
  else:
    selected = owner.historicalSnapshot(options.historicalOrdinal)
  if selected.error != HistoryError.None: return historyFailure[JsonValue](selected.error)
  let saved = selected.value
  # Keep the source lease through export path admission and publication; loaded bytes remain independently owned.
  let head = saved.chainView.bestBlock.value
  let info = head.header.headerInfo
  if info.error != HeaderError.None: return historyFailure[JsonValue](HistoryError.InvalidFormat)
  if uint64(info.value.consumed) > uint64(DefaultHistoricalRecordBytes):
    return historyFailure[JsonValue](HistoryError.LimitExceeded)
  var headerBytes = newSeq[byte](info.value.consumed)
  if encodeOwnedHeader(head.header, headerBytes).error != HeaderError.None:
    return historyFailure[JsonValue](HistoryError.InvalidFormat)
  var output = default(JsonObject)
  output.add("blockHash", json(hexadecimal(array[32, byte](head.blockHash))))
  output.add("stateRoot", json(hexadecimal(array[32, byte](head.stateRoot))))
  output.add("slot", json(head.slot))
  output.add("stateEntries", json(saved.stateSnapshot.value.commitment.entries))
  output.add("bodyAvailable", json(head.hasBlockBody))
  output.add("headerHex", json(hexadecimal(headerBytes)))
  if head.hasBlockBody:
    let body = head.blockBody
    if uint64(body.len) > uint64(DefaultHistoricalRecordBytes): return historyFailure[JsonValue](
        HistoryError.LimitExceeded)
    output.add("blockHex", json(hexadecimal(body)))
  else:
    output.add("blockHex", jsonNull()) # Header-only old seeds still expose their exact complete state without fabricated body bytes.
  let path = options.historicalCheckpointPath
  if path.len > 0:
    let checkpoint = encodeApplicationCheckpoint(saved, DefaultHistoricalRecordBytes)
    if checkpoint.error != ApplicationCheckpointError.None:
      return historyFailure[JsonValue](HistoryError.LimitExceeded)
    let written = exportHistoricalCheckpoint(options.stateDatabase, path, checkpoint.value, DefaultHistoricalRecordBytes)
    if written != HistoryError.None: return historyFailure[JsonValue](written)
    output.add("checkpoint", json(path))
  historySuccess(json(output))
