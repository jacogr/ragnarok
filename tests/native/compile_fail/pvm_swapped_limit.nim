## Reject attempts to bypass the PVM ownership/result or nominal-domain boundary.
import ../../../src/pvm/program
discard decodeProgram([], CodeAddress(0), JumpCountLimit(0), JumpCountLimit(0))
