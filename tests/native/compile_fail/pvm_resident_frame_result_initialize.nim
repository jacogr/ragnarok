# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Actual exclusive frame ownership must survive ordinary caller assignment.

# @@Verification={"group":"ownership_compile","build_name":"pvm-resident-frame-result-initialize","expected":"'=dup' is not available for type <FlatResult[FlatFrame]>","rationale":"The actual FlatResult[FlatFrame] owns resident bytes and borrowed execution descriptors; an ordinary borrowed initialize would duplicate release authority across live frame lifetimes.","reference":"src/pvm/internal/handler_stream.nim"}
import std/assertions
import ../../../src/pvm/machine
import ../../../src/pvm/internal/handler_stream
import ../../support/pvm_resident_frames

proc duplicate(source: FlatResult[FlatFrame]): FlatResult[FlatFrame] =
  ## The genuine source remains live after attempted ordinary initialization.
  var copied = source
  assert source.error == FlatError.None
  move(copied)

var source = populatedFrameResult()
var copied = duplicate(source)
assert source.error == FlatError.None
