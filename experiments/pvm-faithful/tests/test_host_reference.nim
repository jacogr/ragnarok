# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Public host operations compared against independent complete-memory/reference status witnesses.

import std/[assertions, syncio]
import ../engine

proc word(data: string, at, width: int): uint64 =
  ## Bound independently framed reference fields before decoding them.
  assert at >= 0 and width >= 0 and at <= data.len and width <= data.len-at
  result = 0
  for index in 0..<width: result = result or (uint64(byte(data[at+index])) shl (8*index))

var data = ""
try: data = readFile("build/pvm-faithful/host.bin")
except: quit 2
assert data.len >= 12 and data[0..7] == "PVFHST01" and word(data, 8, 4) == 840
var cursor = 12
for mode in 0..<2:
  let dynamic = mode == 1
  let parsed = fromParts(ProgramParts(encodedCode: sharedBytes([0'u8, 0, 1, 0, 1]),
    roSize: 4096, rwSize: 4096, stackSize: 4096,
    ro: sharedBytes([1'u8, 2, 3, 4]), rw: sharedBytes([5'u8, 6, 7, 8])))
  assert parsed.ok
  let admitted = newModule(parsed.blob, dynamic, metered = false)
  assert admitted.ok
  var instance = newInstance(admitted.module)
  for sample in 0..<420:
    assert word(data, cursor, 1) == uint64(mode)
    let operation = word(data, cursor+1, 1)
    let address = uint32(word(data, cursor+2, 4))
    let length = uint32(word(data, cursor+6, 4))
    let expected = word(data, cursor+10, 1)
    cursor += 11
    instance.resetMemory()
    if dynamic:
      var initial = default(array[4096, byte])
      for index in 0..<4096: initial[index] = 33
      for base in [65536'u32, 69632, 77824]:
        assert instance.mapZeroMemory(base, 4096, false) == HostError.None
        assert instance.writeMemory(base, initial) == HostError.None
      assert instance.protectMemory(69632, 4096, true) == HostError.None
    var buffer = newSeq[byte](int(length))
    for index in 0..<buffer.len: buffer[index] = 0xa5
    let status = case operation
      of 0: instance.readMemory(address, buffer)
      of 1: instance.writeMemory(address, buffer)
      of 2: instance.zeroMemory(address, length)
      of 3: instance.mapZeroMemory(address, length, false)
      of 4: instance.mapZeroMemory(address, length, true)
      of 5: instance.protectMemory(address, length, true)
      else: instance.protectMemory(address, length, false)
    if uint64(ord(status)) != expected:
      echo "host mode=", mode, " sample=", sample, " op=", operation, " address=", address,
        " length=", length, " actual=", ord(status), " expected=", expected
    assert uint64(ord(status)) == expected, "faithful public host status mismatch"
    if operation == 0:
      for index in 0..<buffer.len:
        assert buffer[index] == byte(data[cursor+index]), "faithful public read prefix mismatch"
      cursor += buffer.len
    let pages = int(word(data, cursor, 1))
    cursor += 1
    for page in 0..<pages:
      let base = uint32(word(data, cursor, 4))
      let readable = word(data, cursor+4, 1) == 1
      cursor += 5
      var bytes = default(array[4096, byte])
      assert (instance.readMemory(base, bytes) == HostError.None) == readable
      if readable:
        for index in 0..<4096:
          assert bytes[index] == byte(data[cursor+index]), "faithful public host full memory mismatch"
        cursor += 4096
        let writable = word(data, cursor, 1) == 1
        cursor += 1
        assert (instance.writeMemory(base, [bytes[0]]) == HostError.None) == writable,
          "faithful public host protection mismatch"
assert cursor == data.len
echo "faithful public host reference passed: 840 complete-memory cases"
