# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A failed/default light result cannot expose its inactive success payload.
# @@Verification={"group":"privacy","expected":"completed"}
import ../../../src/app/light/head as light_head
let outcome = default(LightHeadResult[LightApplicationHead])
discard outcome.completed
