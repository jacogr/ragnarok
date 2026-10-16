## Code identities cannot silently substitute for preimage lookup identities.
import ../../../src/[state_service_values, work_digest, bounded]
discard servicePreimageKey(ServiceIndex(0), default(CodeHash), ByteLimit(32))
