# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bounded execution metadata with contiguous small stores and lazy large chunks.
## One chunk spans a small extent, so a directory would add an allocation and
## indirection while retaining the same payload. Large extents allocate only
## touched chunks. An exclusive frame or stream moves the store.

import std/assertions

const MetadataChunkElements = 1024

type
  MetadataChunks[T] = ref object
    ## Private large-store directory and logical and allocated extents.
    length, allocated: int
    entries: seq[seq[T]]
  MetadataStore*[T] = object
    ## Small stores carry one checked sequence. Large bookkeeping is allocated separately.
    direct: seq[T]
    sparse: nil MetadataChunks[T]

proc `=copy`*[T](destination: var MetadataStore[T], source: MetadataStore[T]) {.error.}
  ## Copying could share a mutable large directory between invocations.

proc `=dup`*[T](source: MetadataStore[T]): MetadataStore[T] {.error.}
  ## Borrow queries and move the store with its exclusive frame or stream.

proc `=wasMoved`*[T](store: var MetadataStore[T]) {.nodestroy, inline.} =
  ## Clear both moved owners; a moved store has no remaining logical extent.
  `=wasMoved`(store.direct)
  `=wasMoved`(store.sparse)

proc initMetadataStore*[T: HasDefault](length: int): MetadataStore[T] =
  ## Bound the complete logical extent before choosing the small allocation or directory.
  if length < 0 or length > 4194304: return default(MetadataStore[T])
  if length <= MetadataChunkElements:
    # The direct sequence holds the complete small extent.
    return MetadataStore[T](direct: newSeq[T](length))
  let chunks = length div MetadataChunkElements + int(length mod MetadataChunkElements != 0)
  var entries = newSeq[seq[T]](chunks)
  if entries.len != chunks: return default(MetadataStore[T])
  let sparse: nil MetadataChunks[T] = MetadataChunks[T](length: length)
  if sparse == nil: return default(MetadataStore[T])
  sparse.entries = move(entries)
  MetadataStore[T](sparse: sparse)

func len*[T](store: MetadataStore[T]): int {.inline.} =
  ## Logical length includes unwritten elements of a large store.
  let sparse {.cursor.} = store.sparse
  if sparse == nil: store.direct.len else: sparse.length

func allocatedElements*[T](store: MetadataStore[T]): int =
  ## Count payload elements; the directory and headers are separate overhead.
  let sparse {.cursor.} = store.sparse
  if sparse == nil: store.direct.len else: sparse.allocated

func `[]`*[T: HasDefault](store: MetadataStore[T], index: int): T {.inline.} =
  ## The checked direct guard also selects the fast path; missing large chunks read as zero.
  if index >= 0 and index < store.direct.len: return store.direct[index]
  let sparse {.cursor.} = store.sparse
  if sparse == nil:
    # A direct store can reach this path only with an invalid index.
    assert false, "metadata index outside direct storage"
    return default(T)
  assert index >= 0 and index < sparse.length
  let chunk = index div MetadataChunkElements
  if sparse.entries[chunk].len == 0: return default(T)
  sparse.entries[chunk][index mod MetadataChunkElements]

proc writeMetadata*[T: HasDefault](store: var MetadataStore[T], index: int,
    value: T): bool {.inline.} =
  ## Allocate a large chunk only after checking its logical slot.
  if index >= 0 and index < store.direct.len:
    store.direct[index] = value
    return true
  let sparse {.cursor.} = store.sparse
  if sparse == nil or index < 0 or index >= sparse.length: return false
  let chunk = index div MetadataChunkElements
  if sparse.entries[chunk].len == 0:
    # The last chunk may have fewer than the default number of elements.
    let count = min(MetadataChunkElements, sparse.length-chunk*MetadataChunkElements)
    sparse.entries[chunk] = newSeq[T](count)
    if sparse.entries[chunk].len != count: return false
    sparse.allocated += count
  sparse.entries[chunk][index mod MetadataChunkElements] = value
  true

proc singletonMetadataStore*[T: HasDefault](value: T): MetadataStore[T] =
  ## The isolated one-instruction plan captures one initialized element.
  result = initMetadataStore[T](1)
  discard writeMetadata(result, 0, value)
