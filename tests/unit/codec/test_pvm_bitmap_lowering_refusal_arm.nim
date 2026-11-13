# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Drive the selected native bitmap lowerer through recoverable allocation refusal.

import std/syncio
when defined(arm64) and (defined(linux) or defined(macosx)):
  import ../../support/pvm_bitmap_lowering_refusal
  runBitmapLoweringRefusal()
echo "PVM bitmap lowering refusal passed"
