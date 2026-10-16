## A preimage hash is not an already derived 31-byte state key.
import ../../../src/[state_service_values, bounded]
discard captureServiceValue(ServiceIndex(0), default(ServicePreimageHash), @[], ByteLimit(0))
