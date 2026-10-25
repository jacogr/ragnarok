# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Callers cannot forge a prepared target or substitute the expected source incarnation.
# @@Verification={"group":"privacy","expected":"target"}
import ../../../src/app/light_store
let prepared = default(PreparedLightPublication)
discard prepared.target
