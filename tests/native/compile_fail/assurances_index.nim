# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Intentional nominal domain misuse must fail compilation.
import ../../../src/codec/assurances
let value: ValidatorIndex = CoreCount(0)
discard value
