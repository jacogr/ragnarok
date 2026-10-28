# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "data"}

## Prepared value sets cannot expose their canonical identities or forge admission.

import ../../../src/state/preimages as state_preimages
var plan: PreparedPreimageValues
discard plan.data
