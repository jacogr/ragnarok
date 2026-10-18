# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A proven absent assignment has no readable child or registration field.
import std/assertions
import ../../../src/codec/state_availability
let assignment = absentAssignment()
assert not assignment.present
discard assignment.guarantee
