# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Exhaustive selected boundary products for page admission, region reservation and heap slack.

import std/[assertions, syncio]
import ../memory_layout

proc word(data: string, cursor: var int): uint32 =
  ## Decode and advance one bounded oracle word, separately from candidate geometry calculations.
  assert cursor >= 0 and cursor <= data.len-4
  result = 0
  for index in 0..<4: result = result or (uint32(byte(data[cursor+index])) shl (8*index))
  cursor += 4

var data = ""
try:
  data = readFile("build/pvm-faithful/layout.bin")
except:
  quit 2
assert data.len >= 12 and data[0..7] == "PVFLAY01"
var cursor = 8
let count = word(data, cursor)
assert count == 59049
let empty = default(SharedBytes)
var accepted = 0
for row in 0..<int(count):
  let page = word(data, cursor)
  let ro = word(data, cursor)
  let rw = word(data, cursor)
  let stack = word(data, cursor)
  let aux = word(data, cursor)
  let expected = byte(data[cursor])
  cursor += 1
  assert expected <= 1
  let answer = buildLayout(page, ro, rw, stack, aux, empty, empty)
  assert answer.ok == (expected == 1), "faithful layout admission mismatch"
  if answer.ok:
    accepted += 1
    let map = answer.layout()
    let actual = [map.pageSize, map.roAddress, map.rwAddress, map.stackLow, map.stackHigh,
      map.auxAddress, map.roSize, map.rwSize, map.stackSize, map.auxSize, map.heapBase,
      map.maxHeapSize]
    for field in actual:
      assert field == word(data, cursor), "faithful layout geometry mismatch"
assert cursor == data.len
echo "faithful layout reference passed: ", count, ", accepted: ", accepted
