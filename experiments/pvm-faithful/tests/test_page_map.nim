# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Validate page-map ordering and ownership under ascending, descending and permuted insertions.

import std/[assertions, syncio]
import ../page_map

for order in 0..2:
  # 4096 entries force several tree levels and every insertion-position split alternative.
  var tree = default(PageMap)
  for index in 0..<4096:
    let key = uint32(if order == 0: index elif order == 1: 4095-index else: (index*2053) mod 4096)
    let page = tree.insertPage(key*4096, 16)
    let data = page.data
    assert data != nil
    data[0] = byte(key and 255)
    data[1] = byte(key shr 8)
    if index mod 127 == 0: tree.validate()
  tree.validate()
  assert tree.count == 4096
  for index in 0..<4096:
    let page = tree.find(uint32(index)*4096)
    assert page != nil
    let data = page.data
    assert data != nil and page.length == 16
    assert data[0] == byte(index and 255) and data[1] == byte(index shr 8)
    for offset in 2..<16: assert data[offset] == 0
  assert tree.find(1) == nil and tree.find(0xffffffff'u32) == nil
  var cursor = tree.lowerBound(1)
  var key = 0'u32
  for index in 1..<4096:
    # Successor traversal crosses internal keys and multiple ancestor levels.
    let page = cursor.next(0xffffffff'u32, key)
    assert page != nil and key == uint32(index)*4096
  assert cursor.next(0xffffffff'u32, key) == nil
  var bounded = tree.lowerBound(4096)
  assert bounded.next(8192, key) != nil and key == 4096
  assert bounded.next(8192, key) != nil and key == 8192
  assert bounded.next(8192, key) == nil
  var retained = move(tree)
  assert tree.count == 0 and tree.find(0) == nil
  retained.validate()
  retained.clear()
  retained.validate()
  let page = retained.insertPage(0xffffffff'u32, 8)
  assert page.length == 8
  retained.validate()
echo "faithful B-tree ordering and ownership passed"
