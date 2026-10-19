# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Rejected misuse: retained snapshot and result/variant state remain private.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

## Verification: {"group": "privacy", "expected": "outputKind"}

import ../../../src/codec/[owned, composite]
discard OwnedWorkInfo(outputKind: WorkKind.Success, payloadLength: 0)
