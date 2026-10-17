## External callers cannot expose, retag or fabricate authorization results or retained nested rows.
import ../../../src/codec/[state_authorization, state_trie]
let value = default(AuthorizationResult[AuthorizerHash])
discard value.completed
