# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Actual exclusive frame ownership must survive ordinary caller assignment.

# @@Verification={"group":"ownership_compile","build_name":"pvm-resident-frame-result-overwrite","expected":"'=dup' is not available for type <FlatResult[FlatFrame]>","rationale":"The actual FlatResult[FlatFrame] owns resident bytes and borrowed execution descriptors; an ordinary borrowed overwrite would duplicate release authority across live frame lifetimes.","reference":"src/pvm/internal/handler_stream.nim"}
import std/assertions
import ../../../src/pvm/machine
import ../../../src/pvm/internal/handler_stream
import ../../support/pvm_resident_frames

proc overwrite(destination: var FlatResult[FlatFrame], source: FlatResult[FlatFrame]) =
  ## A live destination must not retire its owner then acquire a second release of the borrowed source.
  destination = source
  assert source.error == FlatError.None

var source = populatedFrameResult()
var destination = populatedFrameResult()
overwrite(destination, source)
assert source.error == FlatError.None
