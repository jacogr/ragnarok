# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject bypasses of private ownership/results or nominal address/resource domains.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

# @@Verification={"group": "nominal", "expected": "[2] expected: MemoryAddress but got: uint64", "early": ["load(", "[2] expected: MemoryAddress but got: uint64"]}

import ../../../src/pvm/machine as pvm_machine
discard load(default(Memory), 0'u64, AccessWidth(1))
