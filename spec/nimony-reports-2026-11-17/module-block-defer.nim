# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Standalone reproducer: module block defer reaches the C emitter unlowered on the tested pin.

import std/syncio

block:
  defer: echo "done"
