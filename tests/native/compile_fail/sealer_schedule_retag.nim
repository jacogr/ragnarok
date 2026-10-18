# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Callers cannot manufacture successful selection by changing the private result discriminator.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

import ../../../src/state/sealer_schedule
var hidden = default(SealerScheduleResult)
hidden.status = SealerScheduleError.None
