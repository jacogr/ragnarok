# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Ordinary proofs and complete ring-proof bundles are distinct domains.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

## Verification: {"group": "nominal", "expected": "got: BsSignature but wanted: BsRingProof"}

import ../../../src/bandersnatch/bandersnatch
let value: BsRingProof = default(BsSignature)
discard value
