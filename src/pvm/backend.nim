# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Closed engine identities bind prepared owners and completed observations; no CLI policy lives here.
type PvmBackend* {.pure.} = enum
  ## The independent engine and explicit upstream engines never silently substitute for one another.
  Interpreted = "interpreted", PolkaInterpreted = "polkavm-interpreted",
      PolkaCompiled = "polkavm-compiled"

const PolkaVmRevision* = "69e5b87c9888bc4f94cabdadc9661cf68a1bfbfa"
  ## Loaded optional bridges must match the pristine pinned public runtime.
