# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Result storage stays private; failed/default snapshots cannot be exposed or retagged.
import ../../../src/state/validator_state
var hidden = default(ValidatorStateResult)
hidden.status = ValidatorStateError.None
