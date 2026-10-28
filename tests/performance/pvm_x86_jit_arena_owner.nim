# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
## Exercise the real private arena owner after publication, including moved-source observation.
import std/syncio
include ../../src/pvm/internal/x86_jit

proc transfer(owner: sink X86Arena): X86Arena =
  ## Return the exclusive mapping through a genuine consuming call boundary.
  owner

for iteration in 0..<1000:
  # Repeated allocation and retirement exercise the actual OS owner and its generated sink.
  var original = X86Arena(handle: createNative())
  assert original.handle != nil
  var code = [0xc3'u8]
  let offset = publishNative(original.handle, addr code[0], 1)
  assert offset >= 0
  when defined(pvmX86ArenaCopy):
    # Observing the source later makes this an illegal duplicate, rather than a last-use move.
    var destination = transfer(original)
  else:
    # Explicit moves leave an observable disarmed source while the mapping remains callable.
    var destination = transfer(move(original))
    assert original.handle == nil
    var registers = default(array[13, uint64])
    assert callNative(destination.handle, uint32(offset), addr registers[0]) == 1
  assert original.handle == nil

echo "X86_ARENA_MOVE_OK,1000"
