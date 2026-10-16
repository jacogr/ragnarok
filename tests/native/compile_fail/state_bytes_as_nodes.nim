## Payload-byte policy cannot silently replace a trie-node work budget.
import ../../../src/[state_trie, bounded]
var bytes: ByteLimit
let limits = StateTrieLimits(nodes: bytes)
discard limits
