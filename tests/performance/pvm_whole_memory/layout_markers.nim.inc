# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
## Private owned source fragment; the projector removes exactly these three comment lines.
  layout.readTag = 11
  layout.readPointer = cast[pointer](0x1010'u64)
  layout.writeTag = 22
  layout.writePointer = cast[pointer](0x2020'u64)
  layout.epochPointer = cast[pointer](0x3030'u64)
  layout.readEpoch = 33
  layout.writeEpoch = 44
  layout.fastLoads = 55
  layout.fastStores = 66
  layout.slowLoads = 77
  layout.slowStores = 88
  layout.testProbe = cast[pointer](0x4040'u64)
  layout.status = 0x123456789abcdef0'u64