## Dictionary ordinals cannot select configured core positions.
import ../../../src/state_privileges
let owner = default(PrivilegeSnapshot)
discard privilegeAssignerAt(owner, PrivilegeEntryIndex(0))
