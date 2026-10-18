## Reject attempts to bypass the PVM ownership/result or nominal-domain boundary.
import ../../../src/pvm/program
let result = default(ProgramResult[Program])
discard result.completed
