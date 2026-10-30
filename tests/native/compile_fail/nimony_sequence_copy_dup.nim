# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Sequence ownership hooks must propagate the element's copy prohibition.
# @@Verification={"group":"ownership_compile","expected":"'=dup' is not available for type <seq[SequenceOwner]>","build_name":"nimony-sequence-copy-dup","rationale":"Sequence duplication used to bypass even explicit error copy AND dup hooks; preserve this second original #2737 reproduction rather than infer it from the copy-only case.","reference":"spec/nimony-nightly-2026-10-21.md"}
import std/syncio
type SequenceOwner = object ## A scalar-only exclusive element requires no artificial destructor.
  token: int
proc `=copy`(target: var SequenceOwner, source: SequenceOwner) {.error.}
  ## Exclusive element identity cannot be duplicated through a sequence.
proc `=dup`(source: SequenceOwner): SequenceOwner {.error.}
  ## Explicit duplication is also forbidden.
var original: seq[SequenceOwner] = @[]
original.add SequenceOwner(token: 7)
var duplicate = original
echo original[0].token, duplicate[0].token # Both sequences remain live, preventing a move.
