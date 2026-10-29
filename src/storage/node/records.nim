# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Detached physical trie records carry complete child identities independently of JAM B encoding.
## These mutable transport objects own copied bytes and confer no validation or chain authority.

import ../../codec/state/[trie as state_trie, layout as state_layout]
import ../../codec/bounded

type
  TrieRecordKind* {.pure.} = enum ## Explicit physical leaf/branch forms; codecs must validate tags.
    Leaf, Branch
  TrieRecord* = object ## Untrusted detached input/output; unused fields must be canonical zero/empty.
    kind*: TrieRecordKind
    digest*: StateNodeHash
    key*: StateKey
    payload*: seq[byte]
    left*, right*: StateNodeHash
  RecordCollection* = object ## Detached physical record union carries no single-root metadata or graph authority.
    records*: seq[TrieRecord]
  TrieExport* = object ## Complete target metadata plus records absent from the declared base revision.
    base*, root*: StateRoot
    entries*: uint64
    nodes*: uint64
    records*: seq[TrieRecord]
  TrieExportLimits* = object ## Bound record descriptors and aggregate copied raw leaf values separately.
    records*: TrieNodeLimit
    valueBytes*: ByteLimit
