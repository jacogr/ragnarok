## White-box tests use only our own module to reach private-wire aliases; external probes enforce privacy.
include ../../src/bitstrings

# Only successfully validated snapshots authorize private backing-allocation fixture setup.
proc checked[T](parsed: BitResult[T]): T =
  doAssert parsed.error == BitError.None
  parsed.value

let limit = BitLimit(8)
let owner = checked(decodeBits(@[8'u8, 0x81], limit)).owner
# Reserve real backing capacity for a variable output while restoring the exact validated payload.
owner.data.packed.setLen(16)
owner.data.packed.setLen(1)
let wire = cast[ptr UncheckedArray[byte]](addr owner.data.packed[0])
doAssert encodeOwnedBits(owner, limit, wire.toOpenArray(0, 1)).error == BitError.AliasedBuffers
doAssert encodeOwnedFixedBits(owner, BitCount(8), limit, wire.toOpenArray(0, 0)).error ==
    BitError.AliasedBuffers
doAssert owner.data.packed[0] == 0x81
echo "Nim bits: immutable private-wire alias checks passed"
