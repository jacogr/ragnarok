# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Each failed/default Boolean/bitstring result read runs in its own checked optimized process.
import std/[cmdline, syncio]
import ../../src/codec/bitstrings
let useDefault = paramStr(2) == "default"
var output: seq[byte] = @[]
case paramStr(1)
of "boolean-value":
  # No failed/default operation authorizes application data, ownership or progress.
  let parsed = if useDefault: default(BitResult[BooleanRead]) else: decodeBoolean([byte(2)])
  echo ord(parsed.value.value)
of "boolean-consumed":
  # No failed/default operation authorizes application data, ownership or progress.
  let parsed = if useDefault: default(BitResult[BooleanRead]) else: decodeBoolean([])
  echo parsed.value.consumed
of "variable-owner":
  # No failed/default operation authorizes application data, ownership or progress.
  let parsed = if useDefault: default(BitResult[BitsRead]) else: decodeBits([], BitLimit(9))
  echo ord(bitsInfo(parsed.value.owner).error)
of "variable-consumed":
  # No failed/default operation authorizes application data, ownership or progress.
  let parsed = if useDefault: default(BitResult[BitsRead]) else: decodeBits([byte(9), 0], BitLimit(9))
  echo parsed.value.consumed
of "fixed-owner":
  # No failed/default operation authorizes application data, ownership or progress.
  let parsed = if useDefault: default(BitResult[BitsRead]) else: decodeFixedBits([byte(255)],
      BitCount(1), BitLimit(1))
  echo ord(bitsInfo(parsed.value.owner).error)
of "fixed-consumed":
  # No failed/default operation authorizes application data, ownership or progress.
  let parsed = if useDefault: default(BitResult[BitsRead]) else: decodeFixedBits([], BitCount(1),
      BitLimit(0))
  echo parsed.value.consumed
of "info-count":
  # No failed/default operation authorizes application data, ownership or progress.
  let parsed = if useDefault: default(BitResult[BitsInfo]) else: bitsInfo(default(OwnedBits))
  echo uint64(parsed.value.count)
of "info-packed":
  # No failed/default operation authorizes application data, ownership or progress.
  let parsed = if useDefault: default(BitResult[BitsInfo]) else: bitsInfo(default(OwnedBits))
  echo parsed.value.packedBytes
of "bit":
  # No failed/default operation authorizes application data, ownership or progress.
  let parsed = if useDefault: default(BitResult[bool]) else: bitAt(default(OwnedBits), 0)
  echo ord(parsed.value)
of "bit-index":
  # No failed/default operation authorizes application data, ownership or progress.
  let parsed = if useDefault: default(BitResult[bool]) else: bitAt(decodeBits([byte(0)], BitLimit(
      0)).value.owner, 0)
  echo ord(parsed.value)
of "boolean-write":
  # No failed/default operation authorizes application data, ownership or progress.
  let parsed = if useDefault: default(BitResult[int]) else: encodeBoolean(true, output)
  echo parsed.value
of "variable-write":
  # No failed/default operation authorizes application data, ownership or progress.
  let parsed = if useDefault: default(BitResult[int]) else: encodeBits([true], BitLimit(1), output)
  echo parsed.value
of "fixed-write":
  # No failed/default operation authorizes application data, ownership or progress.
  let parsed = if useDefault: default(BitResult[int]) else: encodeFixedBits([true], BitCount(0),
      BitLimit(0), output)
  echo parsed.value
of "owned-variable-write":
  # No failed/default operation authorizes application data, ownership or progress.
  let parsed = if useDefault: default(BitResult[int]) else: encodeOwnedBits(default(OwnedBits),
      BitLimit(0), output)
  echo parsed.value
of "owned-fixed-write":
  # No failed/default operation authorizes application data, ownership or progress.
  let parsed = if useDefault: default(BitResult[int]) else: encodeOwnedFixedBits(default(OwnedBits),
      BitCount(0), BitLimit(0), output)
  echo parsed.value
else:
  # An unknown trusted selector is a fixture error.
  quit(2)
