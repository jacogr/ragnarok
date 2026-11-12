# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Private bounded execution metadata with stable logical indices and lazy zero-filled chunks.
## Small extents use one direct payload: their first write would allocate the whole extent anyway.
## Larger extents read missing chunks as zero; the first write allocates only its own chunk.
## Frame/stream ownership supplies exclusive mutation. This module retains no guest byte pointers.

import std/assertions

const MetadataChunkElements = 1024

type MetadataStore*[T] = object
  ## Logical extent is fixed; only large extents use a lazily populated directory.
  length: int
  direct: seq[T]
  chunks: seq[seq[T]]
  allocated: int

proc `=wasMoved`*[T](store: var MetadataStore[T]) {.nodestroy, inline.} =
  ## Delegate sequence retirement and clear scalar extents; compiler-generated moves clear owning fields only.
  `=wasMoved`(store.direct)
  `=wasMoved`(store.chunks)
  store.length = 0
  store.allocated = 0

proc initMetadataStore*[T: HasDefault](length: int): MetadataStore[T] =
  ## Small extents avoid a redundant directory; large extents admit only directory space.
  assert length >= 0 and length <= 4194304
  if length <= MetadataChunkElements:
    # Small hot maps need one checked sequence access, with no directory allocation or chunk lookup.
    return MetadataStore[T](length: length, direct: newSeq[T](length), allocated: length)
  MetadataStore[T](length: length,
    chunks: newSeq[seq[T]](length div MetadataChunkElements + int(
        length mod MetadataChunkElements != 0)))

func len*[T](store: MetadataStore[T]): int {.inline.} =
  ## The full admitted extent does not change when a chunk is first written.
  store.length

func allocatedElements*[T](store: MetadataStore[T]): int =
  ## Copied payload occupancy excludes the fixed directory and allocator overhead.
  store.allocated

func `[]`*[T: HasDefault](store: MetadataStore[T], index: int): T {.inline.} =
  ## Preserve checked logical bounds and the zero value of an unmaterialized source slot.
  if store.direct.len > 0: return store.direct[index]
  assert index >= 0 and index < store.length
  let chunk = index div MetadataChunkElements
  if store.chunks[chunk].len == 0: return default(T)
  store.chunks[chunk][index mod MetadataChunkElements]

proc `[]=`*[T: HasDefault](store: var MetadataStore[T], index: int, value: T) {.inline.} =
  ## Direct payloads stay contiguous; a first large-store write initializes its chunk before publication.
  if store.direct.len > 0:
    # The sequence check enforces the same admitted logical bound on this direct path.
    store.direct[index] = value
    return
  assert index >= 0 and index < store.length
  let chunk = index div MetadataChunkElements
  if store.chunks[chunk].len == 0:
    # A short final chunk never allocates beyond the admitted logical extent.
    let count = min(MetadataChunkElements, store.length-chunk*MetadataChunkElements)
    store.chunks[chunk] = newSeq[T](count)
    store.allocated += count
  store.chunks[chunk][index mod MetadataChunkElements] = value

proc singletonMetadataStore*[T: HasDefault](value: T): MetadataStore[T] =
  ## The single-instruction adapter reserves exactly one initialized element.
  result = initMetadataStore[T](1)
  result[0] = value
