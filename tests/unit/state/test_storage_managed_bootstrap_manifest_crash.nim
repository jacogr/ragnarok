# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bootstrap process death must preserve forensic files and cannot silently overwrite an existing target.
import std/assertions
import std/syncio
import ../../support/storage_io
import ../../support/storage_crash_bootstrap
proc main() {.raises.} =
  ## Independently count genuine creation boundaries before killing after every selected successful syscall.
  for operation in [renameIo]:
    let count = bootstrapCrashCase("storage_managed_bootstrap_manifest_crash-control", true,
        operation, 4096)
    assert count > 0 and count < 32
    for skip in 0..<int(count):
      assert bootstrapCrashCase("storage_managed_bootstrap_manifest_crash-killed", true, operation,
          cint(skip)) == uint64(skip)+1
try:
  main()
except:
  quit(2)
echo "PASS storage_managed_bootstrap_manifest_crash: actual CURRENT replacement, complete seeded map and absent-only retry"
