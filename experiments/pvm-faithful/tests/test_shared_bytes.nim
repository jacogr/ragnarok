# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Retained slices outlive their parent handle without copying or exposing mutable storage.

import std/[assertions, syncio]
import ../shared_bytes

proc retained(): SharedBytes =
  ## Return a slice after dropping the original owning handle.
  let source = sharedBytes([11'u8, 22, 33, 44, 55])
  let slice = source.slice(1, 3)
  assert (unsafeAddr source.view()[1]) == (unsafeAddr slice.view()[0])
  slice

for iteration in 0..<1000:
  # Repeated release and reborrow exposes a lost ARC owner under AddressSanitizer.
  let source = retained()
  assert source.len == 3 and source.view()[0] == 22 and source.view()[2] == 44
  let empty = source.slice(3, 0)
  assert empty.len == 0 and empty.view().len == 0
  let nested = source.slice(1, 1)
  assert readBits[1](nested, 0) == 33
let empty = default(SharedBytes)
assert empty.view().len == 0
echo "faithful shared byte slices passed"
