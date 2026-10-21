# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Every actual bootstrap sync boundary resumes EINTR and refuses unconfirmed ownership on EIO.
import std/[assertions, syncio]
import ../../support/storage_bootstrap_faults
proc main() {.raises.} =
  ## Discover bounded native barriers independently for both physical layouts.
  for managed in [false, true]:
    let count = bootstrapCase("storage-bootstrap-baseline", managed, 0, 0)
    assert count > 0 and count < 32
    for skip in 0..<int(count):
      assert bootstrapCase("storage-bootstrap-eintr", managed, cint(skip), 2) == count+2
      discard bootstrapCase("storage-bootstrap-eio", managed, cint(skip), 1, true)
try:
  main()
except:
  quit(2)
echo "PASS storage bootstrap barriers: every interruption/refusal, forensic bytes, absent-only retry and strict admission"
