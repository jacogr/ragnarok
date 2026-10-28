# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Compilation must reject raw integers in the host byte-copy budget domain.

# @@Verification={"group": "nominal", "expected": "got: uint64 but wanted: MemoryByteLimit"}

import ../../../src/pvm/machine as pvm_machine
# A local policy record isolates the nominal field contract from unrelated owner validation.
type Policy = object
  limit: MemoryByteLimit
discard Policy(limit: 1'u64)
