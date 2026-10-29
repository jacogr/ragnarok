# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "completed"}

## Refuse raw construction or retagging of original-block-bound validator activity.

import ../../../src/state/validator/activity as validator_activity
var outcome: ValidatorActivityResult[PreparedValidatorActivity]
discard outcome.completed
