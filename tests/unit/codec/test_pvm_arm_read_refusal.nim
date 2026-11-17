# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Incomplete ARM reads and refused child images must not publish native code.

import std/syncio
import ../../../src/pvm/internal/[arm64_jit, native_read_body]

when NativeCheckedReadEnabled:
  # The real ARM read path and private malformed-metadata controls execute only on a supported native target.
  witnessArmReadGuards()
echo "PVM ARM read refusal passed"
