# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## External code cannot retag a failed result as finalized success.
# @@Verification={"group": "privacy", "expected": "status"}

import ../../../src/app/current_block_input as app_current_block_input
var outcome = default(CurrentBlockInputResult)
outcome.status = CurrentBlockInputError.None
