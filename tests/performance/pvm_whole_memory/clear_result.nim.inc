# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
## Private owned source fragment; the projector removes exactly these three comment lines.
  context.slowLoads = context.loads
  context.slowStores = context.stores
  context.loads += context.fastLoads
  context.stores += context.fastStores
  clearWindows(addr context)
  context.epochPointer = nil
  context.testProbe = nil
  context.writer = nil # No borrowed authority or host pointer escapes a completed invocation.