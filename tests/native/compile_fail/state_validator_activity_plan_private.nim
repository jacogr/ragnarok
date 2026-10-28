# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "data"}

## Refuse raw construction or retagging of original-block-bound validator activity.

import ../../../src/state/validator_activity as state_validator_activity
var owner: PreparedValidatorActivity
discard owner.data
