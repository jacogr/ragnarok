# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## White-box tests use only our own module to reach private-wire aliases; external probes enforce privacy.
import std/[assertions, syncio]
include ../../../src/codec/bitstrings

# Only successfully validated snapshots authorize private backing-allocation fixture setup.
proc checked[T](parsed: BitResult[T]): T =
  assert parsed.error == BitError.None
  parsed.value

let limit = BitLimit(8)
let owner = checked(decodeBits(@[8'u8, 0x81], limit)).owner
let data = owner.data
assert data != nil
# Reserve real backing capacity for a variable output while restoring the exact validated payload.
data.packed.setLen(16)
data.packed.setLen(1)
let wire = cast[ptr array[16, byte]](addr data.packed[0])
assert encodeOwnedBits(owner, limit, wire[].toOpenArray(0, 1)).error == BitError.AliasedBuffers
assert encodeOwnedFixedBits(owner, BitCount(8), limit, wire[].toOpenArray(0, 0)).error ==
    BitError.AliasedBuffers
assert data.packed[0] == 0x81
echo "Nim bits: immutable private-wire alias checks passed"
