# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Error copy hooks must reject scalar-only owners without requiring an artificial destructor.
# @@Verification={"group": "ownership_compile", "expected": "'=dup' is not available for type <ScalarOwner>", "build_name": "nimony-scalar-copy"}

import std/syncio
type ScalarOwner = object ## A scalar payload deliberately has no destructor or managed field.
  token: int
proc `=copy`(destination: var ScalarOwner, source: ScalarOwner) {.error.}
  ## Exclusive scalar state cannot be copied even without runtime cleanup.
proc `=dup`(source: ScalarOwner): ScalarOwner {.error.}
  ## Implicit duplication must honor the same exclusion.
var original = ScalarOwner(token: 7)
var duplicate = original
echo original.token, duplicate.token # Both values remain live, so this cannot be a move.
