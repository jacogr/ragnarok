# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A proven absent assignment has no readable child or registration field.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

# @@Verification={"group": "contracts", "expected": "assignment.isPresent"}

import std/assertions
import ../../../src/codec/state/availability as state_availability
let assignment = absentAssignment()
assert not assignment.present
discard assignment.guarantee
