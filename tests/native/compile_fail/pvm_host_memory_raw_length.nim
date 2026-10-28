# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Compilation must reject raw integers in the host range length domain.

# @@Verification={"group": "nominal", "expected": "got: uint64 but wanted: MemoryLength"}

import ../../../src/pvm/machine as pvm_machine
# A local policy record isolates the nominal field contract from unrelated owner validation.
type Request = object
  length: MemoryLength
discard Request(length: 1'u64)
