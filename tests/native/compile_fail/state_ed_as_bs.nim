# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Different public-key schemes retain nominal roles even at the same encoded width.
import ../../../src/codec/state_safrole
let key = default(StateEdKey)
let validator = StateValidator(bandersnatch: key)
discard validator
