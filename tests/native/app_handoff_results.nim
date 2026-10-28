# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Idle handoffs and services expose no completed outcome through the consuming accessor.

import std/cmdline
import ../../src/app/services as app_services
import ../../src/app/handoff as app_handoff

let argument = paramStr(1)
if argument == "service":
  var owner = default(Services)
  discard owner.takeAccumulation() # Default service ownership has no completed adoption to acknowledge.
else:
  var owner = default(AccumulationHandoff)
  discard owner.take() # Idle is not an implicit default completion.
