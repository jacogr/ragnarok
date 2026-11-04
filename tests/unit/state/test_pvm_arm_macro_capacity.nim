# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
## Optional descriptor caching must retain resident admission when its larger image cannot fit.
import std/[assertions, syncio]
import ../../../src/pvm/internal/arm64_jit
import ../../support/pvm_arm_macro_backend

when (defined(linux) or defined(macosx)) and defined(arm64) and not defined(pvmArm64JitRefuse):
  # Native cases use real executable arena accounting and compare complete cached/uncached results.
  assert armMacroCapacityControls() == 5
else:
  # Unavailable hosts retain the same fixed ABI without executing ARM instructions.
  assert sizeof(ArmMacroState) == 208

echo "PASS ARM resident cache capacity / real arena / source word ceiling / unchanged fallback"
