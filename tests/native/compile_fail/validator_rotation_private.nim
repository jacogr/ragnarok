# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Failed/default plans cannot expose mutable success storage.
import ../../../src/state/validators
let hidden = default(ValidatorRotationResult)
discard hidden.completed
