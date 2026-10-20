# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject copies of the composite application owner, including its nested listener/exporter fields.
## Only one stable owner may be borrowed by native callbacks and dispatcher turns.

# @@Verification={"group": "ownership_compile", "expected": "'=dup' is not available for type <Services>", "build_name": "app-services-copy"}

import ../../../src/app/services
var original = default(Services)
var duplicate = original
original.close()
duplicate.close()
