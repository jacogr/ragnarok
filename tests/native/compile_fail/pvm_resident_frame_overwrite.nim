# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
## Actual exclusive frame ownership must survive ordinary caller assignment.
# @@Verification={"group":"ownership_compile","build_name":"pvm-resident-frame-overwrite","expected":"'=dup' is not available for type <FlatFrame>","rationale":"The actual FlatFrame owns resident bytes and borrowed execution descriptors; an ordinary borrowed overwrite would duplicate release authority across live frame lifetimes.","reference":"src/pvm/internal/handler_stream.nim"}
import std/assertions
import ../../../src/pvm/machine
import ../../../src/pvm/internal/handler_stream
import ../../support/pvm_resident_frames

proc overwrite(destination: var FlatFrame, source: FlatFrame) =
  ## A live destination must not retire its owner then acquire a second release of the borrowed source.
  destination = source
  assert uint64(source.info.gas) == 10000

var source = populatedFrame()
var destination = populatedFrame()
overwrite(destination, source)
assert uint64(source.info.gas) == 10000
