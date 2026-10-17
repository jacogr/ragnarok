## Integration callers cannot forge success or mutate private snapshot/bank storage.
import ../../../src/quic/integration
import ../../../src/codec/owned
discard IntegrationResult[int](status: IntegrationError.None)
