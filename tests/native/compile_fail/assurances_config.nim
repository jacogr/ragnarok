# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Intentional nominal domain misuse must fail compilation.
import ../../../src/codec/assurances
let value = AssuranceConfig(cores: ValidatorCount(2), validators: CoreCount(6))
discard value
