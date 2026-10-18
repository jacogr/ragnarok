## Reject attempts to bypass the PVM ownership/result or nominal-domain boundary.
import ../../../src/pvm/program
var result = default(ProgramResult[Program])
result.status = ProgramError.None
