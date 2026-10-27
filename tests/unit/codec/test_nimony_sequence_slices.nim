# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Sequence slicing retains exact ranges and independent mutable ownership after upstream #2782.
import std/[assertions, syncio]
let data = @[1, 2, 3]
assert data[0..0] == @[1] # The original two-line reproducer must instantiate successfully.
assert data[1..^1] == @[2, 3] # Backwards bounds select the complete inclusive suffix.
assert data[0..<2] == @[1, 2] # Half-open prefixes retain the original decoder truncation extent.
assert data[0..<0].len == 0 and data[1..<1].len ==
    0 # Zero and interior empty prefixes remain explicit test cases.
var copied = data[0..^1]
copied[0] = 9
assert data == @[1, 2, 3] # Mutating the returned buffer cannot change its original owner.
let words = @["one", "two", "three"]
var selected = words[1..^1]
selected[0].add('!')
assert selected == @["two!", "three"] and words[1] == "two" # Nested strings retain independent value semantics.
echo "nimony-sequence-slices: ok"
