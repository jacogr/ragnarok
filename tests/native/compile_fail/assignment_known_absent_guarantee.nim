## A proven absent assignment has no readable child or registration field.
import std/assertions
import ../../../src/codec/state_availability
let assignment = absentAssignment()
assert not assignment.present
discard assignment.guarantee
