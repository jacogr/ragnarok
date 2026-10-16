## Integration callers cannot forge success or mutate private snapshot/bank storage.
import ../../../src/quic/integration
import ../../../src/codec/owned
var checked = default(IntegrationResult[PreimageKey])
discard checked.completed
