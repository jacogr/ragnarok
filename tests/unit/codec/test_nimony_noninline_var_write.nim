# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## NIM-008 regression: optimized reads must observe a non-inlined callee's write to a local.
import std/[assertions, syncio]

proc bump(value: var int) {.noinline.} =
  ## Preserve a real call boundary; inlining hid the original missing-write summary.
  inc value

proc verifyMutation() =
  ## Keep the integer local so constant propagation cannot ignore the mutable call's effect.
  var value = 1
  bump(value)
  assert value == 2, "a non-inlined var call updates its caller's local"

verifyMutation()
echo "nimony-noninline-var-write: ok"
