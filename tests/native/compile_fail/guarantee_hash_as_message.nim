# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A raw digest cannot substitute for the domain-prefixed message.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

## Verification: {"group": "nominal", "expected": "got: Blake2bHash but wanted: GuaranteeMessage"}

import ../../../src/crypto/[primitives, guarantee]
let value: GuaranteeMessage = default(Blake2bHash)
discard value
