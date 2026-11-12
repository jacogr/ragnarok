# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Check lazy standard-memory regions, host/guest permissions, reset and memory limits.
## Literal expectations exercise upstream StandardMemory contracts; differential qualification follows.

import std/[assertions, syncio]
import ../standard_memory

let layout = MemoryLayout(pageSize: 4096, roAddress: 0x10000, rwAddress: 0x20000,
  roSize: 4096, rwSize: 8192, stackLow: 0xfffd0000'u32, stackHigh: 0xfffe0000'u32,
  stackSize: 65536, auxAddress: 0xffff0000'u32, auxSize: 4096,
  heapBase: 0x22000, maxHeapSize: 0x100000,
  ro: sharedBytes([1'u8, 2, 3, 4]), rw: sharedBytes([5'u8, 6, 7, 8]))
var memory = newStandardMemory(layout)
assert memory.residentLengths() == [0, 0, 0]
assert load[4](memory, 0x10000).value == 0x04030201
assert load[8](memory, 0x20000).value == 0x08070605
assert load[8](memory, 0x21000).value == 0
assert load[8](memory, 0xfffdfff8'u32).value == 0
assert memory.residentLengths() == [0, 0, 0]
assert store[1](memory, 0x10000, 9).kind == AccessKind.Trap
assert store[1](memory, 0xffff0000'u32, 9).kind == AccessKind.Trap
assert memory.write(0xffff0000'u32, [0x99'u8]) == AccessKind.Ok
assert load[1](memory, 0xffff0000'u32).value == 0x99
assert store[8](memory, 0x20002, 0x8877665544332211'u64).kind == AccessKind.Ok
assert load[8](memory, 0x20002).value == 0x8877665544332211'u64
assert load[2](memory, 0x20000).value == 0x0605
assert memory.residentLengths() == [4096, 0, 4096]
assert store[8](memory, 0xfffdfff8'u32, 0x0123456789abcdef'u64).kind == AccessKind.Ok
assert memory.residentLengths() == [4096, 4096, 4096]
assert store[1](memory, 0xfffd0000'u32, 0x77).kind == AccessKind.Ok
assert load[8](memory, 0xfffdfff8'u32).value == 0x0123456789abcdef'u64
assert load[1](memory, 0xfffd0000'u32).value == 0x77
assert memory.residentLengths() == [4096, 65536, 4096]
assert store[8](memory, 0x21ffc, 0xffffffffffffffff'u64).kind == AccessKind.Trap
assert load[4](memory, 0x21ffc).value == 0
assert load[1](memory, 0xfffe0000'u32).kind == AccessKind.Trap
let grown = memory.growHeap(layout, 1)
assert grown.ok and grown.top == 0x22001
assert load[1](memory, 0x22000).kind == AccessKind.Ok
assert load[1](memory, 0x23000).kind == AccessKind.Trap
memory.reset(layout)
assert memory.residentLengths() == [0, 0, 0]
assert load[8](memory, 0x20000).value == 0x08070605
assert load[8](memory, 0xfffdfff8'u32).value == 0
assert load[1](memory, 0xffff0000'u32).value == 0

block:
  # The same virtual span can be valid while its requested resident allocation exceeds policy.
  var limited = newStandardMemory(layout)
  limited.setLimits(4096, 4096)
  assert store[1](limited, 0x20000, 1).kind == AccessKind.Ok
  assert store[1](limited, 0xfffdffff'u32, 1).kind == AccessKind.MemoryLimit
  assert limited.residentLengths() == [4096, 0, 0]
  assert load[1](limited, 0xfffdffff'u32).value == 0

echo "faithful standard memory lazy regions and reset passed"
