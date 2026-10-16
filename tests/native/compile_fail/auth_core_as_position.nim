## Core ordinals cannot silently become positions inside a pool or queue.
import ../../../src/codec/state_authorization
let owner = default(AuthorizationSnapshot)
let core = default(AuthorizationCoreIndex)
let hash = authorizerAt(owner, core, core)
discard hash
