# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Binding and commitment payloads/discriminators remain private across all alternatives.
import ../../../src/crypto/extrinsic_commitment
import ../../../src/codec/header
var hidden = default(ExtrinsicCommitmentResult[ExtrinsicRoot])
discard hidden.completed
