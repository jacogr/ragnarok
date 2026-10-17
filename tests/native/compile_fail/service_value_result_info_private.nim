## Successful service-value payloads are private behind the guarded accessor.
import ../../../src/codec/[state_service_values, state_trie]
let parsed = default(ServiceValueResult[ServiceValueInfo])
discard parsed.completed
