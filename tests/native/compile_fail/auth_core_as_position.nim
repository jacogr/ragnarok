## Core ordinals cannot silently become positions inside a pool or queue.
import ../../../src/state_authorization
var owner: AuthorizationSnapshot
var core: AuthorizationCoreIndex
let hash = authorizerAt(owner, core, core)
discard hash
