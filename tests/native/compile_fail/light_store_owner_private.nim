# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Callers cannot borrow the light application's native writer outside its excluded owner.
# @@Verification={"group":"privacy","expected":"writer"}
import ../../../src/app/light_store
var store = default(LightPagedStore)
discard store.writer
