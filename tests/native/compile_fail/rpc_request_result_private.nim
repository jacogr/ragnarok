# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Negative compiler fixture: failed request lookups cannot be retagged to expose fabricated history.
# @@Verification={"group": "privacy", "expected": "status"}

import ../../../src/chain/services
var decoded = default(ServiceRequestResult)
decoded.status = ServiceReadError.None
