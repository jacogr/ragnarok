## Successful account payloads are private behind the guarded result accessor.
import ../../../src/codec/[state_accounts, state_trie]
let parsed = default(ServiceMetadataResult[ServiceMetadataRead])
discard parsed.completed
