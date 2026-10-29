# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Private backing cannot grant forged partial runtime or transport authority.
# @@Verification={"group":"privacy","expected":"current"}
import ../../../src/app/light/runtime as light_runtime
var runtime = default(LightRuntime)
discard runtime.current
