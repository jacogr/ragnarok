# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Callers cannot manufacture successful selection by changing the private result discriminator.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

# @@Verification={"group": "privacy", "expected": "status"}

import ../../../src/state/sealer_state as state_sealer_state
import ../../../src/state/sealer_schedule as state_sealer_schedule
var hidden = default(SealerStateResult)
hidden.status = SealerScheduleError.None
