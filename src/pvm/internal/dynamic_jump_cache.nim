# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Shared geometry for invocation-owned checked jump tags and their native readers.
## A tag holds the positive original table ordinal in its high word and the resolved
## header plus one in its low word. Zero is empty. Bucket selection grants no target
## authority: every reader compares the full ordinal before using the cached header.
## The fixed nine-bit index retains hot ordinal pairs separated by 256 with one probe.
## Storage stays bounded at 4 KiB per allocated frame cache. Frames clear tags on resume
## and lend their stable storage only during synchronous native execution.

const
  DynamicJumpCacheBits* = 9 ## Both ISA masks use this width; no runtime policy selects another size.
  DynamicJumpCacheSlots* = 1 shl DynamicJumpCacheBits ## Fixed power-of-two storage for direct indexing.
  DynamicJumpCacheMask* = DynamicJumpCacheSlots-1 ## Bucket selection retains only these low ordinal bits.

# Both native encodings require a nonempty, bounded contiguous low-bit mask.
when DynamicJumpCacheBits < 1 or DynamicJumpCacheBits > 12:
  {.error: "jump tags require a bounded 1..12-bit index encodable by both native readers".}

type DynamicJumpTags* = array[DynamicJumpCacheSlots, uint64]
  ## A copied storage shape; the private frame owns allocation, invalidation and target authority.

func dynamicJumpSlot*(ordinal: uint64): range[0..DynamicJumpCacheMask] {.inline.} =
  ## Derive a bounded host bucket without validating an original table ordinal or target.
  int(ordinal and uint64(DynamicJumpCacheMask))
