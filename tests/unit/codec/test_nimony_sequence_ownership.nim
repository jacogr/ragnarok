# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Explicit moves of noncopyable sequence elements remain valid alongside rejection guards.
import std/assertions
import std/syncio
type SequenceOwner = object ## Scalar-only owner mirrors the negative fixtures without fake cleanup.
  token: int
proc `=copy`(target: var SequenceOwner, source: SequenceOwner) {.error.}
  ## Copying exclusive element identity is forbidden.
proc `=dup`(source: SequenceOwner): SequenceOwner {.error.}
  ## Implicit element duplication is forbidden too.
proc transfer(): seq[SequenceOwner] =
  ## Return the admitted owner by move, retaining its exact scalar payload.
  var owned: seq[SequenceOwner] = @[]
  owned.add SequenceOwner(token: 7)
  result = move(owned)
let accepted = transfer()
assert accepted.len == 1 and accepted[0].token == 7
echo "nimony-sequence-ownership: ok"
