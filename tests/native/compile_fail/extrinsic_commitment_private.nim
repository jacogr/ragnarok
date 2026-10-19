# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Binding and commitment payloads/discriminators remain private across all alternatives.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

## Verification: {"group": "privacy", "expected": "completed"}

import ../../../src/crypto/extrinsic_commitment
import ../../../src/codec/header
var hidden = default(ExtrinsicCommitmentResult[ExtrinsicRoot])
discard hidden.completed
