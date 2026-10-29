# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Journal frame result alternatives remain success/selected-error guarded.
import std/[assertions, cmdline, syncio]
import ../../src/storage/[journal_codec, record_codec]
import ../../src/storage/node/[records as node_records, repository as node_repository]
import ../../src/codec/bounded
import ../../src/codec/state/trie as state_trie
proc main() =
  ## Dynamic origins cover both payload families and the nested refusal diagnostic.
  let member = paramStr(1)
  let origin = paramStr(2)
  let limits = RecordLimits(encoded: ByteLimit(105), records: TrieExportLimits(
      records: TrieNodeLimit(1)))
  let limit = ByteLimit(153)
  if member == "bytes":
    let empty = default(FrameResult[seq[byte]])
    let selected = if origin == "default": empty
      elif origin == "failed": encodeJournalFrame(RepositoryGeneration(0), default(TrieExport),
          limits, limit)
      else: encodeJournalFrame(RepositoryGeneration(1), default(TrieExport), limits, limit)
    echo selected.value.len
  elif member == "reason":
    let empty = default(FrameResult[seq[byte]])
    let selected = if origin == "default": empty else: encodeJournalFrame(RepositoryGeneration(1),
      TrieExport(records: @[default(TrieRecord)]), limits, limit)
    echo ord(selected.recordError)
  else:
    let empty = default(FrameResult[JournalFrame])
    let wire = encodeJournalFrame(RepositoryGeneration(1), default(TrieExport), limits, limit).value
    let selected = if origin == "default": empty
      elif origin == "failed": decodeJournalFrame([], limits, limit)
      else: decodeJournalFrame(wire, limits, limit)
    echo uint64(selected.value.generation)
main()
