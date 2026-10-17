## Integration callers cannot forge success or mutate private snapshot/bank storage.
import ../../../src/quic/integration
import ../../../src/codec/owned
var bank = default(IntegrationBank)
discard bank.wires
