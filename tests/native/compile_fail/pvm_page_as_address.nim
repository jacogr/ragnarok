# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject bypasses of private ownership/results or nominal address/resource domains.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

# @@Verification={"group": "nominal", "expected": "[2] expected: MemoryAddress but got: PageIndex", "early": ["load(", "[2] expected: MemoryAddress but got: PageIndex"]}

import ../../../src/pvm/machine
discard load(default(Memory), PageIndex(16), AccessWidth(1))
