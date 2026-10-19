# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Private discriminators cannot be supplied through an external variant constructor.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

# @@Verification={"group": "privacy", "expected": "outputKind"}

import ../../../src/codec/[c2_records, composite]
discard OperandOutput(outputKind: WorkKind.Panic)
