# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## SHA-pinned test-only fixed-word hex transport keeps independent arithmetic expectations outside production algorithms.
import std/[assertions, strutils, parseutils, syncio]
proc arithmeticCorpus*(path: string, rows, width: int): seq[seq[byte]] {.raises.} =
  ## Require exact fixed rows/width before decoding trusted fixture records; malformed setup fails the suite.
  let text = readFile(path)
  result = @[]
  for line in text.splitLines():
    if line.len == 0: continue # Permit the fixture's final newline only.
    assert result.len < rows and line.len == width*2
    var record = newSeq[byte](width)
    for i in 0..<width:
      var octet: byte = 0
      assert parseHex(line[2*i..2*i+1], octet) == 2
      record[i] = octet # Exact complete octets, no normalization or alternate framing.
    result.add(record)
  assert result.len == rows
proc corpusWord*(record: openArray[byte], offset: int): uint64 =
  ## Decode one exact E8 test word after a subtraction-based extent check.
  assert record.len >= 8 and offset >= 0 and offset <= record.len-8
  result = 0'u64
  for i in 0..<8:
    result = result or (uint64(record[offset+i]) shl (8*i)) # Every shift is within one E8 word.
