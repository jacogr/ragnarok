# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bounded execution metadata with contiguous small stores and lazy large chunks.
## One chunk spans a small extent, so a directory would add an allocation and
## indirection while retaining the same payload. Large extents allocate only
## touched chunks. An exclusive frame or stream moves the store. Read/write operations
## validate logical and physical extents and report refusal explicitly. Unwritten valid
## sparse cells are zero values; callers separately establish sealed source-fact authority.

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

func tryReadMetadata*[T: HasDefault](store: MetadataStore[T], index: int,
    value: var T): bool {.inline.} =
  ## Read a proven logical/physical cell; refusal preserves output. An unwritten valid sparse
  ## cell succeeds with its default value, which callers must distinguish from a sealed source fact.
  if index < 0: return false
  if index < store.direct.len:
    value = store.direct[index]
    return true
  let sparse {.cursor.} = store.sparse
  if sparse == nil or index >= sparse.length: return false
  let chunks = sparse.length div MetadataChunkElements + int(
      sparse.length mod MetadataChunkElements != 0)
  if sparse.entries.len != chunks: return false
  let chunk = index div MetadataChunkElements
  let payload {.cursor.} = sparse.entries[chunk]
  if payload.len == 0:
    # Missing allocation is an intentional zero cell only inside the complete admitted directory.
    value = default(T)
    return true
  let count = min(MetadataChunkElements, sparse.length-chunk*MetadataChunkElements)
  if payload.len != count: return false
  value = payload[index mod MetadataChunkElements]
  true

proc writeMetadata*[T: HasDefault](store: var MetadataStore[T], index: int,
    value: T): bool {.inline.} =
  ## Admit the complete directory/leaf before access or allocation; failed writes preserve existing cells.
  if index >= 0 and index < store.direct.len:
    store.direct[index] = value
    return true
  let sparse {.cursor.} = store.sparse
  if sparse == nil or index < 0 or index >= sparse.length: return false
  let chunks = sparse.length div MetadataChunkElements + int(
      sparse.length mod MetadataChunkElements != 0)
  if sparse.entries.len != chunks: return false
  let chunk = index div MetadataChunkElements
  let count = min(MetadataChunkElements, sparse.length-chunk*MetadataChunkElements)
  if sparse.entries[chunk].len == 0:
    # A temporary complete leaf preserves the old implicit-zero cell on allocation refusal.
    if sparse.allocated < 0 or sparse.allocated > sparse.length-count: return false
    var payload = newSeq[T](count)
    if payload.len != count: return false
    sparse.entries[chunk] = move(payload)
    sparse.allocated += count
  elif sparse.entries[chunk].len != count:
    return false
  sparse.entries[chunk][index mod MetadataChunkElements] = value
  true

proc singletonMetadataStore*[T: HasDefault](value: T): MetadataStore[T] =
  ## The isolated one-instruction plan captures one initialized element.
  result = initMetadataStore[T](1)
  discard writeMetadata(result, 0, value)

when defined(pvmSharedAsyncWitness):
  proc probeMetadataReadRefusals*(): bool =
    ## Actual direct/sparse ownership refuses invalid bounds and incomplete directory/leaves without outputs.
    var direct = initMetadataStore[uint32](4)
    if not writeMetadata(direct, 0, 7): return false
    var value = 99'u32
    for index in [-1, 4, high(int)]:
      if tryReadMetadata(direct, index, value) or value != 99: return false
    if not tryReadMetadata(direct, 0, value) or value != 7: return false
    if not tryReadMetadata(direct, 1, value) or value != 0: return false
    var sparse = initMetadataStore[uint32](1025)
    if not writeMetadata(sparse, 1024, 33): return false
    if not tryReadMetadata(sparse, 1024, value) or value != 33: return false
    if not tryReadMetadata(sparse, 0, value) or value != 0: return false
    let owned {.cursor.} = sparse.sparse
    if owned == nil: return false
    owned.entries[0] = @[17'u32]
    value = 99
    if tryReadMetadata(sparse, 0, value) or value != 99 or writeMetadata(sparse, 0, 5): return false
    if owned.entries[0] != @[17'u32]: return false
    owned.entries.setLen(0)
    if tryReadMetadata(sparse, 1024, value) or value != 99 or writeMetadata(sparse, 1024, 5):
      return false
    true
