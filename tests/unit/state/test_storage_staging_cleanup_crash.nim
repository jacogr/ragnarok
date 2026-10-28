# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Cleanup process death leaves exact bounded removals without changing the selected head or farther files.
import std/assertions
import std/syncio
import ../../support/storage_io
import ../../support/storage_crash_cleanup
proc main() {.raises.} =
  ## Kill after every real unlink and directory sync, then independently reopen and explicitly finish cleanup.
  for operation in [unlinkIo, syncIo]:
    let count = cleanupCrashCase("storage_staging_cleanup_crash-control", false, operation, 4096)
    assert count == 3
    for skip in 0..<int(count):
      assert cleanupCrashCase("storage_staging_cleanup_crash-killed", false, operation, cint(
          skip)) == uint64(skip)+1
try:
  main()
except:
  quit(2)
echo "PASS storage_staging_cleanup_crash: exact bounded removals, selected-byte preservation, strict restart and farther epochs"
