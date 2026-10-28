# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Dynamic codec payload guards retain default/failed reasons and genuine valid controls.
import std/assertions
import std/cmdline
import std/syncio
import ../../src/storage/record_codec as storage_record_codec
import ../../src/storage/node_records as storage_node_records
import ../../src/codec/bounded as codec_bounded
import ../../src/codec/state_trie as codec_state_trie

proc main() =
  ## Dynamic selection prevents constant folding from replacing native precondition evidence.
  let member = paramStr(1)
  let origin = paramStr(2)
  let policy = RecordLimits(encoded: ByteLimit(105))
  if member == "bytes":
    let empty = default(RecordResult[seq[byte]])
    let selected = if origin == "default": empty
      elif origin == "failed": encodeTrieExport(default(TrieExport), default(RecordLimits))
      else: encodeTrieExport(default(TrieExport), policy)
    echo selected.value.len
  else:
    let empty = default(RecordResult[TrieExport])
    let encoded = encodeTrieExport(default(TrieExport), policy).value
    let selected = if origin == "default": empty
      elif origin == "failed": decodeTrieExport([], policy)
      else: decodeTrieExport(encoded, policy)
    echo selected.value.entries
main()
