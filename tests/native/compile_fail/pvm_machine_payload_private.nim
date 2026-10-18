## Reject bypasses of private ownership/results or nominal address/resource domains.
import ../../../src/pvm/machine
let outcome = default(MachineResult[Memory])
discard outcome.completed
