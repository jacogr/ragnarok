## Retained arrays remain private; callers cannot mutate them through owner handles.
import ../../../src/state_privileges
let owner = default(PrivilegeSnapshot)
discard owner.data
