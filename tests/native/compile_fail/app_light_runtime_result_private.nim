# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Private backing cannot grant forged partial runtime or transport authority.
# @@Verification={"group":"privacy","expected":"completed"}
import ../../../src/app/light_runtime as app_light_runtime
let outcome = default(LightRuntimeResult[int])
discard outcome.completed
