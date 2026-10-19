# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Private result/owner fields cannot be read or retagged by application callers.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

## Verification: {"group": "privacy", "expected": "winnersValue"}

import ../../../src/state/safrole_markers
var hidden = default(SafroleMarkers)
discard hidden.winnersValue
