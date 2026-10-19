# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A static server owner must not duplicate its listener, root or accepted file descriptors.
## Compiler-rejection fixture; compilation must reject copying the composite owner.

# @@Verification={"group": "ownership_compile", "expected": "'=dup' is not available for type <UiServer>", "build_name": "ui-server-copy"}

import ../../../src/ui/server
var original = default(UiServer)
var duplicate = original
original.close()
duplicate.close()
