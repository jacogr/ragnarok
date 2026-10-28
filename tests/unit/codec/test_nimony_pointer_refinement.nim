# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Guarded nullable pointers retain presence across mutations of their pointees after upstream #2809.
import std/[assertions, syncio]

proc touch(value: var int) =
  ## Mutate only the integer; the caller's pointer identity cannot change.
  inc value

proc receive(input: nil ptr int) =
  ## A missing input is inert; an inferred local retains the successful presence proof.
  if input == nil: return
  let receiver = input
  touch(receiver[])
  touch(receiver[])

var value = 1
receive(addr value)
assert value == 3 # Both mutable calls execute through the same inferred pointer.
receive(nil)
assert value == 3 # The absent-pointer alternative cannot mutate unrelated storage.
echo "nimony-pointer-refinement: ok"
