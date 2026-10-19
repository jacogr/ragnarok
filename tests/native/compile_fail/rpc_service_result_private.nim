# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Negative compiler fixture: reject external retagging of a failed service-query result.
## Verification: {"group": "privacy", "expected": "status"}

import ../../../src/chain/services
var decoded = default(ServiceReadResult)
decoded.status = ServiceReadError.None
