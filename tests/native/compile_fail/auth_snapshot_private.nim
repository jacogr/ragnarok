## Caller code cannot replace or expose the private mutable object underlying an immutable snapshot.
import ../../../src/state_authorization
let owner = AuthorizationSnapshot(data: nil)
discard owner
