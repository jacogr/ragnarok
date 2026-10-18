## Reject attempts to bypass the PVM ownership/result or nominal-domain boundary.
import ../../../src/pvm/program
discard instruction(default(Program), 0'u64)
