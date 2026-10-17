## A core ordinal cannot be passed as a header authorization timeslot.
import ../../../src/state/authorization
import ../../../src/codec/state_authorization
let owner = default(AuthorizationSnapshot)
discard advanceAuthorization(owner, owner, [], AuthorizationCoreIndex(0), default(AuthorizationConfig))
