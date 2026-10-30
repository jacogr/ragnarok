# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
## Private invocation-only chunk leases. Raw authority never leaves invoke; generation checks revoke all aliases.
include "./probes.nim.inc"

proc clearWindows(context: ptr Invocation) =
  ## Retire raw authority before every checked callback; old integer tags remain only reacquisition hints.
  context.readPointer = nil
  context.writePointer = nil

proc chunkPointer(writer: ScalarMemoryWriter, key: uint64, writable: bool): nil pointer =
  ## Admit only a real retained readable page or a current-epoch private dirty chunk in the original writer.
  if writer.nativeEpoch == high(uint64): return nil
  let pageTag = key shr 3
  let chunk = int(key and 7)
  var page: nil PageData = nil
  var slot = -1
  if writer.writePage != nil and writer.writeTag == pageTag:
    page = writer.writePage
    slot = writer.writeSlot
  elif writer.spareWritePage != nil and writer.spareWriteTag == pageTag:
    page = writer.spareWritePage
    slot = writer.spareWriteSlot
  elif not writable and writer.readPage != nil and writer.readTag == pageTag:
    page = writer.readPage
  if page == nil or pageTag < 16 or pageTag >= 1048576: return nil
  let held = page
  if held.access != PageAccess.ReadOnly and held.access != PageAccess.ReadWrite: return nil
  if writable:
    # An actual dirty bit belongs to this exact active page/slot and means its whole 512-byte chunk was cloned.
    if held.access != PageAccess.ReadWrite or not writer.active or slot < 0 or
        slot >= writer.pages.len or slot >= writer.dirty.len: return nil
    if writer.pages[slot] != held or (writer.dirty[slot] and (1'u8 shl chunk)) == 0: return nil
  cast[pointer](unsafeAddr held.chunks[chunk].bytes[0])

proc seedWindows(context: ptr Invocation, address: uint64, width: uint64, storing: bool) =
  ## Successful original preflight/COW is the only acquisition boundary; misses retain ordinary helpers.
  let writer {.cursor.} = cast[ScalarMemoryWriter](context.writer)
  if writer == nil or width notin [1'u64, 2, 4, 8]: return
  let start = address and 0xffffffff'u64
  if start < 65536 or start > 0xffffffff'u64-width or (start and 511) > 512-width: return
  context.epochPointer = cast[pointer](addr writer.nativeEpoch)
  context.readTag = start shr 9
  context.readPointer = chunkPointer(writer, context.readTag, false)
  context.readEpoch = writer.nativeEpoch
  if storing: context.writeTag = start shr 9
  context.writePointer = chunkPointer(writer, context.writeTag, true)
  context.writeEpoch = writer.nativeEpoch
  when defined(pvmWholeNativeLeaseControls):
    runLeaseProbe(context, address, width, storing)

proc memoryPaths*(done: Invocation): array[4, uint64] =
  ## Expose only copied counters, never a pointer or chunk capability.
  [done.fastLoads, done.fastStores, done.slowLoads, done.slowStores]
