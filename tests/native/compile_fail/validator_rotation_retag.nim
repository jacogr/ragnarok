# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A caller cannot forge success by modifying a plan result discriminator.
import ../../../src/state/validators
var hidden = default(ValidatorRotationResult)
hidden.status = ValidatorRotationError.None
