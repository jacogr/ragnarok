## Gas is not a role service, even when its numeric value would fit E4.
import ../../../src/codec/state_privileges
let state = PrivilegeState(manager: PrivilegeGas(1))
discard state
